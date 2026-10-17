import test from 'node:test';
import assert from 'node:assert/strict';
import {createRequire} from 'node:module';
import {once} from 'node:events';
import {execFile} from 'node:child_process';
import {promisify} from 'node:util';
import {mkdtemp,writeFile,readFile,rm} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {fileURLToPath} from 'node:url';
import {pcmWav} from '../../WorkFollow/Resources/wf-meeting-http.mjs';
import {readMeetingWav} from '../meeting-wav.mjs';

test('WAV replay preserves samples even when metadata precedes the data chunk',()=>{
  const pcm=Buffer.alloc(17600,1),base=pcmWav(pcm),metadata=Buffer.alloc(12);
  metadata.write('JUNK');metadata.writeUInt32LE(3,4);metadata.set([1,2,3],8);
  const wav=Buffer.concat([base.subarray(0,12),metadata,base.subarray(12)]);
  wav.writeUInt32LE(wav.length-8,4);
  assert.deepEqual(readMeetingWav(wav).pcm,pcm);
  assert.equal(readMeetingWav(wav).duration,0.55);
});

test('saved WAV is replayed via installed Pi with explicit semantic/VAD settings and sentence report',async t=>{
  const require=createRequire('/opt/homebrew/lib/node_modules/@earendil-works/pi-coding-agent/package.json');
  const {WebSocketServer}=require('ws');
  const server=new WebSocketServer({port:0,host:'127.0.0.1'});await once(server,'listening');
  t.after(()=>{for(const client of server.clients)client.terminate();server.close();});
  const bytes=[];
  server.on('connection',socket=>{
    let taskID,started=false;
    const send=(event,payload={})=>socket.send(JSON.stringify({header:{event,task_id:taskID},payload}));
    const sentence=final=>send('result-generated',{output:{sentence:{sentence_id:1,begin_time:100,
      end_time:final?500:null,text:final?'预算两千五百元。':'预算两千五百',sentence_end:final}}});
    socket.on('message',(data,binary)=>{
      if(binary){bytes.push(Buffer.from(data));if(!started){started=true;sentence(false);}return;}
      const event=JSON.parse(String(data));taskID=event.header.task_id;
      if(event.header.action==='run-task'){
        assert.equal(event.payload.parameters.semantic_punctuation_enabled,true);
        assert.equal(event.payload.parameters.max_sentence_silence,1200);send('task-started');
      }else if(event.header.action==='finish-task'){sentence(true);send('task-finished');}
    });
  });
  const root=await mkdtemp(join(tmpdir(),'wf-replay-'));t.after(()=>rm(root,{recursive:true,force:true}));
  const wav=join(root,'recording-asr.wav'),reportPath=join(root,'report.json'),fixture=join(root,'extension.mjs');
  const pcm=Buffer.alloc(17600,1);await writeFile(wav,pcmWav(pcm));
  const moduleURL=new URL('../../WorkFollow/Resources/wf-meeting-stream.mjs',import.meta.url).href;
  await writeFile(fixture,`import extension from ${JSON.stringify(moduleURL)};
    export default pi=>extension(pi,{resolveAudioModel:async()=>({transport:'asr-stream',
      modelID:'qwen-audio-3.1-asr-flash-streaming',url:'ws://127.0.0.1:${server.address().port}',apiKey:'fixture'})});`);
  await promisify(execFile)(process.execPath,[fileURLToPath(new URL('../probe-meeting-recording.mjs',import.meta.url)),
    '--audio',wav,'--report',reportPath,'--extension',fixture,'--model','','--semantic','--silence-ms','1200'],{timeout:15000});
  const report=JSON.parse(await readFile(reportPath,'utf8'));
  assert.deepEqual(Buffer.concat(bytes),pcm);
  assert.equal(report.parameters.semantic_punctuation_enabled,true);
  assert.equal(report.finalText,'预算两千五百元。');assert.equal(report.duration,0.55);
  assert.deepEqual(report.sentences,[{start:0.1,end:0.5,text:'预算两千五百元。'}]);
  assert.ok(report.events.some(event=>event.kind==='preview'));assert.equal(report.error,undefined);
});
