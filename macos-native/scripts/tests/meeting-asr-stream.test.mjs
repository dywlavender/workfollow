import test from 'node:test';
import assert from 'node:assert/strict';
import {createRequire} from 'node:module';
import {once} from 'node:events';
import {spawn} from 'node:child_process';
import {mkdtemp,writeFile,rm} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {MeetingASRInputStream} from '../../WorkFollow/Resources/wf-meeting-asr-stream.mjs';
import {audioModel} from '../../WorkFollow/Resources/wf-meeting-audio.mjs';
const require=createRequire('/opt/homebrew/lib/node_modules/@earendil-works/pi-coding-agent/package.json');
const {WebSocketServer}=require('ws'),{WebSocket}=require('undici');
const pcm=Buffer.alloc(8000,1);
const packet=(sequence=0)=>({version:2,format:'pcm16',sampleRate:16000,channels:1,
  offset:7+sequence*0.25,duration:0.25,sequence,audio:pcm.toString('base64')});

async function service(t,{mode='success'}={}){
  const server=new WebSocketServer({port:0,host:'127.0.0.1'});await once(server,'listening');
  t.after(()=>{for(const client of server.clients)client.terminate();server.close();});
  const commands=[],bytes=[];let previewSent=false;
  server.on('connection',(socket,request)=>{
    assert.equal(request.headers.authorization,'Bearer fixture');let taskID;
    const send=(event,payload={})=>socket.send(JSON.stringify({header:{event,task_id:taskID},payload}));
    const sentence=(text,final=false)=>send('result-generated',{output:{sentence:{sentence_id:1,
      text,begin_time:100,end_time:final?750:null,sentence_end:final}}});
    socket.on('message',(data,binary)=>{
      if(binary){
        bytes.push(Buffer.from(data));
        if(!previewSent){previewSent=true;sentence('预算三千');sentence('预算两千五百');}
        return;
      }
      const event=JSON.parse(String(data));commands.push(event);taskID=event.header.task_id;
      if(event.header.action==='run-task'){
        assert.equal(event.payload.model,'qwen-audio-3.1-asr-flash-streaming');
        assert.equal(event.payload.parameters.format,'pcm');
        assert.equal(event.payload.parameters.sample_rate,16000);
        assert.equal(event.payload.parameters.heartbeat,true);
        send('task-started');
        send('result-generated',{output:{sentence:{heartbeat:true,sentence_id:0}}});
      }else if(event.header.action==='finish-task'){
        if(mode==='timeout')return;
        if(mode==='failed')return socket.send(JSON.stringify({header:{event:'task-failed',task_id:taskID,error_code:'ServiceFailure'}}));
        setTimeout(()=>{
          if(mode!=='missing-final'){
            sentence('预算两千五百元。',true);
            sentence('预算两千五百元。',true);
          }
          send('task-finished');
        },40);
      }
    });
  });
  return {url:`ws://127.0.0.1:${server.address().port}`,commands,bytes};
}
function stream(server,events,timeoutMs=2000){
  return new MeetingASRInputStream({url:server.url,apiKey:'fixture',modelID:'qwen-audio-3.1-asr-flash-streaming',
    offset:7,timeoutMs,emit:event=>events.push(event),socketFactory:(url,options)=>new WebSocket(url,options)});
}

test('Pi registry routes dedicated ASR to inference without changing its authentication',async()=>{
  const connection=await audioModel({model:{id:'qwen-audio-3.1-asr-flash-streaming'},
    modelRegistry:{getApiKeyAndHeaders:async()=>({ok:true,apiKey:'fixture',headers:{'X-Custom':'test'},
      baseUrl:'https://fixture.cn-beijing.maas.aliyuncs.com/v1'})}});
  assert.equal(connection.transport,'asr-stream');
  assert.equal(connection.url,'wss://fixture.cn-beijing.maas.aliyuncs.com/api-ws/v1/inference');
  assert.equal(connection.headers['X-Custom'],'test');
});

test('duplex ASR updates before stop, sends exact binary PCM and drains final before completion',async t=>{
  const server=await service(t),events=[],session=stream(server,events);await session.ready;
  await session.append(packet());
  for(let attempt=0;attempt<100&&!events.some(e=>e.kind==='preview');attempt++)await new Promise(r=>setTimeout(r,5));
  assert.deepEqual(events.filter(e=>e.kind==='preview').map(e=>e.text),['预算三千','预算两千五百']);
  assert.ok(!server.commands.some(e=>e.header.action==='finish-task'),'previews must precede stop');
  assert.equal(await session.append(packet()),true,'ACK retry must not resend PCM');
  await session.append(packet(1));await session.finish();
  assert.deepEqual(Buffer.concat(server.bytes),Buffer.concat([pcm,pcm]));
  assert.deepEqual(server.commands.map(e=>e.header.action),['run-task','finish-task']);
  const finals=events.filter(e=>e.kind==='final');assert.equal(finals.length,1);
  assert.equal(finals[0].text,'预算两千五百元。');assert.equal(finals[0].offset,7.1);
  assert.equal(events.filter(e=>e.kind==='speechStopped')[0].offset,7.75);
  assert.equal(session.closed,true);
});

for(const mode of ['missing-final','failed','timeout']){
  test(`stop ${mode} fails explicitly while preserving delivered previews`,async t=>{
    const server=await service(t,{mode}),events=[],session=stream(server,events,mode==='timeout'?150:2000);
    await session.ready;await session.append(packet());
    await assert.rejects(session.finish(),/未返回定稿|任务失败|超时/);
    assert.equal(events.filter(e=>e.kind==='final').length,0);
    assert.equal(events.filter(e=>e.kind==='error').length,1);
    assert.equal(session.closed,true);
  });
}

test('installed Pi dispatches dedicated ASR and delivers final before the stop ACK',async t=>{
  const server=await service(t);
  const root=await mkdtemp(join(tmpdir(),'wf-pi-asr-'));t.after(()=>rm(root,{recursive:true,force:true}));
  const fixture=join(root,'extension.mjs');
  const moduleURL=new URL('../../WorkFollow/Resources/wf-meeting-stream.mjs',import.meta.url).href;
  await writeFile(fixture,`import extension from ${JSON.stringify(moduleURL)};
    export default pi=>extension(pi,{resolveAudioModel:async()=>({transport:'asr-stream',
      modelID:'qwen-audio-3.1-asr-flash-streaming',url:${JSON.stringify(server.url)},apiKey:'fixture'})});`);
  const child=spawn('/opt/homebrew/bin/pi',['--mode','rpc','--no-session','--no-tools','--no-extensions',
    '--no-skills','--no-prompt-templates','--no-context-files','--offline','--extension',fixture],
    {cwd:root,stdio:['pipe','pipe','ignore']});t.after(()=>child.kill());
  let buffer='',sequence=0;const notices=[];
  child.stdout.on('data',data=>{
    buffer+=String(data);let end;
    while((end=buffer.indexOf('\n'))>=0){
      const line=buffer.slice(0,end);buffer=buffer.slice(end+1);
      try{const event=JSON.parse(line);if(event.type==='extension_ui_request')notices.push(event.message);}catch{}
    }
  });
  async function command(input){
    const id=String(++sequence);
    child.stdin.write(JSON.stringify({type:'prompt',message:'/wf-meeting-stream '+JSON.stringify({...input,id})})+'\n');
    const deadline=Date.now()+15000;
    while(Date.now()<deadline){
      if(notices.some(n=>n?.startsWith('WF_MEETING_ERROR '))||child.exitCode!=null)assert.fail('Pi local ASR failed');
      if(notices.some(n=>n?.startsWith('WF_MEETING_STREAM_ACK ')&&JSON.parse(n.slice('WF_MEETING_STREAM_ACK '.length)).id===id))return;
      await new Promise(resolve=>setTimeout(resolve,5));
    }
    assert.fail('Pi ASR command timed out');
  }
  await command({op:'start',offset:7});await command({op:'append',...packet()});
  await command({op:'stop'});
  const events=notices.filter(n=>n?.startsWith('WF_MEETING_STREAM_EVENT ')).map(n=>JSON.parse(n.slice('WF_MEETING_STREAM_EVENT '.length)));
  assert.deepEqual(events.filter(e=>e.kind==='preview').map(e=>e.text),['预算三千','预算两千五百']);
  assert.deepEqual(events.filter(e=>e.kind==='final').map(e=>e.text),['预算两千五百元。']);
  const stopACK=notices.findIndex(n=>n?.startsWith('WF_MEETING_STREAM_ACK ')&&JSON.parse(n.slice('WF_MEETING_STREAM_ACK '.length)).op==='stop');
  const final=notices.findIndex(n=>n?.startsWith('WF_MEETING_STREAM_EVENT ')&&JSON.parse(n.slice('WF_MEETING_STREAM_EVENT '.length)).kind==='final');
  assert.ok(final<stopACK);assert.deepEqual(Buffer.concat(server.bytes),pcm);
});
