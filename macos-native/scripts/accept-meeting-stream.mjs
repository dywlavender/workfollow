// Pace fictional synthetic PCM through Pi at capture rate. Never saves audio.
import {spawn} from 'node:child_process';
import {fileURLToPath} from 'node:url';
import {writeFile} from 'node:fs/promises';
const expected=[{speaker:'A',voice:'Tingting',text:'今天讨论项目交付，确认下周一提交。'},
  {speaker:'B',voice:'Eddy',text:'同意，预算两千五百元，我负责校对。'}];
const fixture=spawn('/private/tmp/wf-meeting-speech-fixture',[],{stdio:['pipe','pipe','ignore']});
const pieces=[];fixture.stdout.on('data',b=>pieces.push(b));fixture.stdin.end(JSON.stringify(expected));
await new Promise((resolve,reject)=>{fixture.on('error',reject);fixture.on('exit',c=>c===0?resolve():reject(new Error('合成失败')));});
const speech=JSON.parse(Buffer.concat(pieces).toString());
const pcm=Buffer.concat(speech.flatMap(l=>[Buffer.from(l.audio,'base64'),Buffer.alloc(24000)]));
const extension=process.env.MEETING_TEST_EXTENSION||fileURLToPath(new URL('../WorkFollow/Resources/wf-meeting-stream.mjs',import.meta.url));
const child=spawn('/opt/homebrew/bin/pi',['--mode','rpc','--no-session','--no-tools','--no-extensions','--no-skills',
  '--no-prompt-templates','--no-context-files','--offline','--extension',extension,
  // 2026-10-07 起扩展不再内置模型 id（见 `check-meeting-pi.mjs` 同一改动），
  // 所以这里必须把实时模型显式传给 Pi，否则会退回 Pi 默认的纯文本模型、实时会话直接拒绝。
  ...(process.env.WF_MEETING_MODEL?['--model',process.env.WF_MEETING_MODEL]:[])],{cwd:'/private/tmp',stdio:['pipe','pipe','ignore']});
let buffer='',pending,startTime=0,sequence=0;
const report={kind:'Pi-paced-input-stream',synthetic:true,audioSaved:false,expected,duration:pcm.length/32000,events:[]};
function settle(error,value){if(!pending)return;const p=pending;pending=null;clearTimeout(p.timer);error?p.reject(error):p.resolve(value);}
child.on('error',()=>settle(new Error('Pi 启动失败')));child.on('exit',()=>settle(new Error('Pi 提前退出')));
child.stdout.on('data',data=>{
  buffer+=String(data);let end;
  while((end=buffer.indexOf('\n'))>=0){const line=buffer.slice(0,end);buffer=buffer.slice(end+1);let e;try{e=JSON.parse(line);}catch{continue;}
    const message=e.message??'';
    if(message.startsWith('WF_MEETING_STREAM_EVENT ')){
      const event=JSON.parse(message.slice('WF_MEETING_STREAM_EVENT '.length));
      report.events.push({...event,elapsedMs:Math.round(performance.now()-startTime)});
      if(event.kind==='error')settle(new Error(event.message));
    }else if(message.startsWith('WF_MEETING_STREAM_ACK ')){
      const ack=JSON.parse(message.slice('WF_MEETING_STREAM_ACK '.length));if(ack.id===pending?.id)settle(null,ack);
    }else if(message.startsWith('WF_MEETING_ERROR ')||e.type==='extension_error')settle(new Error('Pi 流式扩展失败'));
  }
});
function command(input){return new Promise((resolve,reject)=>{const id=String(++sequence);pending={id,resolve,reject,timer:setTimeout(()=>settle(new Error('流式验收超时')),25000)};
  child.stdin.write(JSON.stringify({type:'prompt',message:'/wf-meeting-stream '+JSON.stringify({...input,id})})+'\n');});}
try{
  await command({op:'start',offset:0});startTime=performance.now();
  for(let i=0;i<pcm.length;i+=8000){
    const packet=pcm.subarray(i,i+8000);
    await command({op:'append',version:2,format:'pcm16',sampleRate:16000,channels:1,offset:i/32000,duration:packet.length/32000,audio:packet.toString('base64')});
    const wait=(i+packet.length)/32-(performance.now()-startTime);
    if(wait>0)await new Promise(resolve=>setTimeout(resolve,wait));
  }
  await command({op:'stop'});
  const previews=report.events.filter(e=>e.kind==='preview'&&e.text.trim());
  report.firstPreviewMs=previews[0]?.elapsedMs;
  report.finalText=report.events.filter(e=>e.kind==='final').map(e=>e.text).join('');
  const normalize=text=>text.replace(/[\p{P}\p{Z}\s]/gu,'');
  report.checks={previewBeforeCaptureEnds:report.firstPreviewMs<report.duration*1000,hasFinalText:!!report.finalText,
    transcriptMatchesFixture:normalize(report.finalText)===normalize(expected.map(l=>l.text).join('')),
    noModelResponseJSONRequired:!report.events.some(e=>e.kind==='error')};
  console.log(JSON.stringify({duration:report.duration,firstPreviewMs:report.firstPreviewMs,finalText:report.finalText,checks:report.checks}));
  if(!Object.values(report.checks).every(Boolean))process.exitCode=1;
}catch(error){report.error=error.message;console.error(error.message);process.exitCode=1;}
finally{child.kill();if(process.argv[2])await writeFile(process.argv[2],JSON.stringify(report,null,2)+'\n');}
