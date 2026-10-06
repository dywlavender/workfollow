import test from 'node:test';
import assert from 'node:assert/strict';
import {createRequire} from 'node:module';
import {once} from 'node:events';
import {PersistentAudioExperiment} from './meeting-persistent-experiment.mjs';
const require=createRequire('/opt/homebrew/lib/node_modules/@earendil-works/pi-coding-agent/package.json');
const {WebSocketServer}=require('ws'),{WebSocket}=require('undici');

async function server(t,{failOnRequest=0,toolOutput=false}={}){
  const server=new WebSocketServer({port:0,host:'127.0.0.1'});await once(server,'listening');
  t.after(()=>{for(const socket of server.clients)socket.terminate();server.close();});
  let connections=0;const events=[];
  server.on('connection',socket=>{
    connections++;let requests=0;
    const reply=e=>socket.send(JSON.stringify(e));
    reply({type:'session.created',session:{id:'local-context-session'}});
    socket.on('message',data=>{
      const event=JSON.parse(String(data));events.push(event);
      if(event.type==='session.update')reply({type:'session.updated'});
      if(event.type==='input_audio_buffer.commit')reply({type:'input_audio_buffer.committed'});
      if(event.type==='response.create'){
        requests++;
        if(requests===failOnRequest)return reply({type:'error'});
        const text=JSON.stringify({version:1,segments:[{text:'turn '+requests,start:0,speaker:'A'}]});
        if(toolOutput)reply({type:'response.function_call_arguments.done',name:'submit_meeting_transcript',call_id:'call-'+requests,arguments:text});
        else {
          reply({type:'response.text.delta',delta:'discard this delta'});
          reply({type:'response.text.done',text});
        }
        reply({type:'response.done',response:{status:'completed'}});
      }
    });
  });
  return {url:`ws://127.0.0.1:${server.address().port}`,events,get connections(){return connections;}};
}
test('three requests preserve one socket/session and reset output per turn',async t=>{
  const service=await server(t);
  const session=new PersistentAudioExperiment({url:service.url,apiKey:'test',socketFactory:(u,o)=>new WebSocket(u,o)});
  t.after(()=>session.close());
  for(let i=1;i<=3;i++){
    const result=JSON.parse(await session.transcribe(Buffer.alloc(3200,1),'turn '+i));
    assert.equal(result.segments[0].text,'turn '+i);
  }
  assert.equal(service.connections,1);assert.equal(session.serverSessionID,'local-context-session');
  assert.equal(session.requestCount,3);
  assert.equal(service.events.filter(e=>e.type==='input_audio_buffer.commit').length,3);
  const updates=service.events.filter(e=>e.type==='session.update');
  assert.ok(updates[0].session.audio);
  assert.ok(updates.every(e=>e.session.temperature===0));
  assert.ok(updates.slice(1).every(e=>!e.session.audio));
});
test('tool output uses final arguments and acknowledges each turn without extra response',async t=>{
  const service=await server(t,{toolOutput:true});
  const session=new PersistentAudioExperiment({url:service.url,apiKey:'test',toolOutput:true,socketFactory:(u,o)=>new WebSocket(u,o)});
  t.after(()=>session.close());
  for(let i=1;i<=3;i++)assert.equal(JSON.parse(await session.transcribe(Buffer.alloc(3200,1),'transcribe')).segments[0].text,'turn '+i);
  // Wait for the final acknowledgement to reach the mock server.
  const deadline=Date.now()+1000;
  while(service.events.filter(e=>e.type==='conversation.item.create').length<3&&Date.now()<deadline)await new Promise(resolve=>setTimeout(resolve,5));
  assert.equal(service.events.filter(e=>e.type==='conversation.item.create').length,3);
  assert.equal(service.connections,1);
  assert.equal(service.events.filter(e=>e.type==='response.create').length,3);
  assert.ok(service.events.filter(e=>e.type==='session.update').every(e=>e.session.tools[0].function.name==='submit_meeting_transcript'));
});
test('error closes context and prevents silently continuing identity after reconnect',async t=>{
  const service=await server(t,{failOnRequest:2});
  const session=new PersistentAudioExperiment({url:service.url,apiKey:'test',socketFactory:(u,o)=>new WebSocket(u,o)});
  t.after(()=>session.close());
  await session.transcribe(Buffer.alloc(3200,1),'one');
  await assert.rejects(session.transcribe(Buffer.alloc(3200,1),'two'));
  await assert.rejects(session.transcribe(Buffer.alloc(3200,1),'three'));
  assert.equal(service.connections,1);assert.equal(session.closed,true);
});
