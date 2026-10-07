import test from 'node:test';
import assert from 'node:assert/strict';
import {createRequire} from 'node:module';
import {once} from 'node:events';
import {MeetingInputStream,finishSilenceMs,vadSilenceDurationMs,bytesPerSecond} from '../../WorkFollow/Resources/wf-meeting-stream.mjs';
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
  // VAD 生命周期（MEETING-AUDIO-002）：started/stopped 原样交给 Native。
  assert.equal(events.filter(e=>e.kind==='speechStarted').length,1);
  const started=events.find(e=>e.kind==='speechStarted');
  assert.equal(started.offset,7.1,'speechStarted 带绝对偏移（offset+audio_start_ms）');
  assert.equal(events.filter(e=>e.kind==='speechStopped').length,1);
  assert.equal(events.filter(e=>e.kind==='final').length,1);
  assert.equal(events.find(e=>e.kind==='final').offset,7.1);
  assert.ok(!server.received.some(e=>['input_audio_buffer.commit','response.create'].includes(e.type)));
});

test('finish silence is semantic and strictly longer than the VAD gate',async t=>{
  // MEETING-AUDIO-002：旧实现补 700ms 静音 < VAD 门限 800ms，最后一句话
  // 可能因 VAD 未闭合而丢失。这里锁死 finishSilenceMs > vadSilenceDurationMs。
  assert.ok(finishSilenceMs>vadSilenceDurationMs,
    `补静音(${finishSilenceMs}ms)必须长于 VAD 门限(${vadSilenceDurationMs}ms)`);
  const server=await service(t),events=[];
  const stream=new MeetingInputStream({url:server.url,apiKey:'test',modelID:'configured-realtime',offset:0,emit:e=>events.push(e),socketFactory:(u,o)=>new WebSocket(u,o)});
  await stream.ready;
  await stream.append({version:2,format:'pcm16',sampleRate:16000,channels:1,offset:0,duration:0.25,sequence:0,audio:Buffer.alloc(8000,1).toString('base64')});
  // 等首包的全部分片（ceil(8000/3200)=3 个事件）落地，再拍快照。
  let before=0;
  for(let i=0;i<200;i++){before=server.received.filter(e=>e.type==='input_audio_buffer.append').length;if(before>=3)break;await new Promise(r=>setTimeout(r,5));}
  await stream.finish();
  const appended=server.received.filter(e=>e.type==='input_audio_buffer.append');
  const silence=appended.slice(before)
    .reduce((sum,e)=>sum+Buffer.from(e.audio,'base64').length,0);
  assert.equal(silence,Math.ceil(finishSilenceMs/1000*bytesPerSecond),
    '停止时补的静音字节数必须由 finishSilenceMs 语义推导');
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

test('forward sequence gaps are rejected instead of silently advancing the watermark',async t=>{
  const server=await service(t),events=[];
  const stream=new MeetingInputStream({url:server.url,apiKey:'test',modelID:'configured-realtime',offset:0,emit:e=>events.push(e),socketFactory:(u,o)=>new WebSocket(u,o)});
  await stream.ready;
  const audio=Buffer.alloc(8000,1).toString('base64');
  // seq 0 正常。
  await stream.append({version:2,format:'pcm16',sampleRate:16000,channels:1,offset:0,duration:0.25,sequence:0,audio});
  // seq 2 跳号（缺 1）：必须显式失败，不允许接受 2。
  await assert.rejects(
    stream.append({version:2,format:'pcm16',sampleRate:16000,channels:1,offset:0.5,duration:0.25,sequence:2,audio}),
    /sequence 缺口|已停止/);
  // 缺口触发 fail 后会话关闭：后续 append 一律拒绝。
  await assert.rejects(
    stream.append({version:2,format:'pcm16',sampleRate:16000,channels:1,offset:0.75,duration:0.25,sequence:3,audio}));
  // 服务端只收到 seq 0 的音频（等异步投递落地）。
  let appended=0;
  for(let i=0;i<200;i++){appended=server.received.filter(e=>e.type==='input_audio_buffer.append').length;if(appended>0)break;await new Promise(r=>setTimeout(r,5));}
  assert.ok(appended>0);
});
