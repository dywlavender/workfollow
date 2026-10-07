import test from 'node:test';
import assert from 'node:assert/strict';
import {createRequire} from 'node:module';
import {once} from 'node:events';
import {MeetingInputStream} from '../../WorkFollow/Resources/wf-meeting-stream.mjs';
const require=createRequire('/opt/homebrew/lib/node_modules/@earendil-works/pi-coding-agent/package.json');
const {WebSocketServer}=require('ws'),{WebSocket}=require('undici');

async function service(t,{fail=false}={}){
  const server=new WebSocketServer({port:0,host:'127.0.0.1'});await once(server,'listening');
  t.after(()=>{for(const client of server.clients)client.terminate();server.close();});
  const received=[];
  server.on('connection',socket=>{
    const send=event=>socket.send(JSON.stringify(event));let began=false;
    socket.on('message',data=>{
      const event=JSON.parse(String(data));received.push(event);
      if(event.type==='session.update'){
        assert.equal(event.session.input_audio_transcription.model,'configured-realtime');
        assert.equal(event.session.turn_detection.create_response,false);send({type:'session.updated'});
      }else if(event.type==='input_audio_buffer.append'){
        if(fail)return send({type:'conversation.item.input_audio_transcription.failed',error:{code:'test'}});
        if(!began){began=true;
          send({type:'input_audio_buffer.speech_started',item_id:'turn',audio_start_ms:100});
          send({type:'conversation.item.input_audio_transcription.delta',item_id:'turn',text:'预算',stash:'三千'});
          send({type:'conversation.item.input_audio_transcription.delta',item_id:'turn',text:'预算',stash:'两千五百'});
        }else if(Buffer.from(event.audio,'base64').every(byte=>byte===0)){
          send({type:'input_audio_buffer.speech_stopped',item_id:'turn'});
          send({type:'input_audio_buffer.committed',item_id:'turn'});
          setTimeout(()=>{
            send({type:'conversation.item.input_audio_transcription.completed',item_id:'turn',transcript:'预算两千五百元。'});
            send({type:'conversation.item.input_audio_transcription.completed',item_id:'turn',transcript:'预算两千五百元。'});
            send({type:'conversation.item.input_audio_transcription.delta',item_id:'turn',text:'stale',stash:''});
          },50);
        }
      }
    });
  });
  return {url:`ws://127.0.0.1:${server.address().port}`,received};
}
test('input stream replaces text+stash, finalizes once, and drains without extra commit/response',async t=>{
  const server=await service(t),events=[];
  const stream=new MeetingInputStream({url:server.url,apiKey:'test',modelID:'configured-realtime',offset:7,emit:e=>events.push(e),socketFactory:(u,o)=>new WebSocket(u,o)});
  await stream.ready;
  const pcm=Buffer.alloc(8000,1);
  await stream.append({version:2,format:'pcm16',sampleRate:16000,channels:1,offset:7,duration:0.25,audio:pcm.toString('base64')});
  await stream.finish();
  assert.deepEqual(events.filter(e=>e.kind==='preview').map(e=>e.text),['预算三千','预算两千五百']);
  assert.equal(events.filter(e=>e.kind==='final').length,1);
  assert.equal(events.find(e=>e.kind==='final').offset,7.1);
  assert.ok(!server.received.some(e=>['input_audio_buffer.commit','response.create'].includes(e.type)));
});
test('transcription failure is surfaced and a closed stream cannot accept audio',async t=>{
  const server=await service(t,{fail:true}),events=[];
  const stream=new MeetingInputStream({url:server.url,apiKey:'test',modelID:'configured-realtime',emit:e=>events.push(e),socketFactory:(u,o)=>new WebSocket(u,o)});
  await stream.ready;
  const input={version:2,format:'pcm16',sampleRate:16000,channels:1,offset:0,duration:0.25,audio:Buffer.alloc(8000,1).toString('base64')};
  await stream.append(input);
  for(let i=0;i<100&&!stream.closed;i++)await new Promise(r=>setTimeout(r,5));
  assert.ok(events.some(e=>e.kind==='error'));
  await assert.rejects(stream.append(input));
});

test('append is idempotent per sequence: duplicates are ACKed but never re-appended',async t=>{
  const server=await service(t),events=[];
  const stream=new MeetingInputStream({url:server.url,apiKey:'test',modelID:'configured-realtime',offset:0,emit:e=>events.push(e),socketFactory:(u,o)=>new WebSocket(u,o)});
  await stream.ready;
  const audio=Buffer.alloc(8000,1).toString('base64');
  const appended=()=>server.received.filter(e=>e.type==='input_audio_buffer.append').length;
  const waitForAppends=async target=>{for(let i=0;i<200&&appended()<target;i++)await new Promise(r=>setTimeout(r,5));return appended();};
  // 首次 seq 0：正常 append。
  let dup=await stream.append({version:2,format:'pcm16',sampleRate:16000,channels:1,offset:0,duration:0.25,sequence:0,audio});
  assert.equal(dup,false);
  const afterFirst=await waitForAppends(1);
  assert.ok(afterFirst>0);
  // ACK 丢失后原样重发 seq 0：必须去重（不再 append），但仍返回成功。
  dup=await stream.append({version:2,format:'pcm16',sampleRate:16000,channels:1,offset:0,duration:0.25,sequence:0,audio});
  assert.equal(dup,true);
  assert.equal(appended(),afterFirst,'重发旧 sequence 不得产生第二次 append');
  // 迟到的更旧 seq（重排到达）：同样去重。
  // seq 1 正常前进水位，再重发 seq 0。
  await stream.append({version:2,format:'pcm16',sampleRate:16000,channels:1,offset:0.25,duration:0.25,sequence:1,audio});
  const afterSecond=await waitForAppends(afterFirst+1);
  dup=await stream.append({version:2,format:'pcm16',sampleRate:16000,channels:1,offset:0,duration:0.25,sequence:0,audio});
  assert.equal(dup,true);
  await new Promise(r=>setTimeout(r,20));
  assert.equal(appended(),afterSecond,'重发迟到旧包不得再 append');
  // 不带 sequence 的旧调用方：保持原行为（不去重）。
  dup=await stream.append({version:2,format:'pcm16',sampleRate:16000,channels:1,offset:0.5,duration:0.25,audio});
  assert.equal(dup,false);
  assert.ok((await waitForAppends(afterSecond+1))>afterSecond);
  await stream.finish();
});
