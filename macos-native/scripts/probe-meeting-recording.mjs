// Replay the saved ASR input via Pi, retaining sentence boundaries and revisions.
import {spawn} from 'node:child_process';
import {readFile,writeFile} from 'node:fs/promises';
import {fileURLToPath} from 'node:url';
import {readMeetingWav} from './meeting-wav.mjs';
const args=process.argv.slice(2);
const option=(name,fallback)=>{const index=args.indexOf(name);return index<0?fallback:args[index+1];};
const file=option('--audio'),reportFile=option('--report');
if(!file||!reportFile)throw new Error('用法：--audio <会议-asr.wav> --report <报告.json> [--semantic] [--silence-ms 800]');
const {pcm,duration}=readMeetingWav(await readFile(file));
const model=option('--model','ali-Pi/qwen-audio-3.1-asr-flash-streaming');
const parameters={max_sentence_silence:Number(option('--silence-ms','800')),
  semantic_punctuation_enabled:args.includes('--semantic')};
if(!Number.isFinite(parameters.max_sentence_silence)||parameters.max_sentence_silence<200||parameters.max_sentence_silence>6000)
  throw new Error('静音断句阈值须为 200～6000ms。');
const extension=option('--extension',fileURLToPath(new URL('../WorkFollow/Resources/wf-meeting-stream.mjs',import.meta.url)));
const child=spawn('/opt/homebrew/bin/pi',['--mode','rpc','--no-session','--no-tools','--no-extensions',
  '--no-skills','--no-prompt-templates','--no-context-files','--offline','--extension',extension,
  ...(model?['--model',model]:[])],
  {cwd:'/private/tmp',stdio:['pipe','pipe','ignore']});
let buffer='',pending,commandID=0,start=0;
const report={kind:'local-recording-replay',audioFile:file,audioSaved:true,model,parameters,duration,
  playbackRate:1,createdAt:new Date().toISOString(),events:[]};
function settle(error,value){
  if(!pending)return;const request=pending;pending=null;clearTimeout(request.timer);
  error?request.reject(error):request.resolve(value);
}
child.on('error',()=>settle(new Error('Pi 无法启动。')));
child.on('exit',()=>settle(new Error('Pi 提前退出。')));
child.stdout.on('data',data=>{
  buffer+=String(data);let end;
  while((end=buffer.indexOf('\n'))>=0){
    const line=buffer.slice(0,end);buffer=buffer.slice(end+1);let event;
    try{event=JSON.parse(line);}catch{continue;}
    const message=event.message??'';
    if(message.startsWith('WF_MEETING_STREAM_EVENT ')){
      const update=JSON.parse(message.slice('WF_MEETING_STREAM_EVENT '.length));
      report.events.push({...update,elapsedMs:Math.round(performance.now()-start)});
      if(update.kind==='error')settle(new Error(update.message));
    }else if(message.startsWith('WF_MEETING_STREAM_ACK ')){
      const ack=JSON.parse(message.slice('WF_MEETING_STREAM_ACK '.length));
      if(ack.id===pending?.id)settle(null,ack);
    }else if(message.startsWith('WF_MEETING_ERROR ')||event.type==='extension_error')settle(new Error('Pi 复测命令失败。'));
  }
});
function command(input){
  return new Promise((resolve,reject)=>{
    const id=String(++commandID);pending={id,resolve,reject,timer:setTimeout(()=>settle(new Error('Pi 复测超时。')),30000)};
    child.stdin.write(JSON.stringify({type:'prompt',message:'/wf-meeting-stream '+JSON.stringify({...input,id})})+'\n');
  });
}
try{
  await command({op:'start',offset:0,parameters});start=performance.now();
  for(let offset=0,sequence=0;offset<pcm.length;offset+=8000,sequence++){
    const packet=pcm.subarray(offset,offset+8000);
    await command({op:'append',version:2,format:'pcm16',sampleRate:16000,channels:1,sequence,
      offset:offset/32000,duration:packet.length/32000,audio:packet.toString('base64')});
    const delay=(offset+packet.length)/32-(performance.now()-start);
    if(delay>0)await new Promise(resolve=>setTimeout(resolve,delay));
  }
  const stop=performance.now();await command({op:'stop'});report.stopDurationMs=Math.round(performance.now()-stop);
  const finals=report.events.filter(event=>event.kind==='final');
  report.firstPreviewMs=report.events.find(event=>event.kind==='preview'&&event.text?.trim())?.elapsedMs;
  report.finalText=finals.map(event=>event.text).join('');
  report.sentences=finals.map(event=>({start:event.offset,
    end:report.events.find(other=>other.kind==='speechStopped'&&other.itemID===event.itemID)?.offset,text:event.text}));
}catch(error){report.error=error.message;process.exitCode=1;}
finally{
  child.kill();await writeFile(reportFile,JSON.stringify(report,null,2)+'\n');
  console.log(JSON.stringify({duration,firstPreviewMs:report.firstPreviewMs,stopDurationMs:report.stopDurationMs,
    sentenceCount:report.sentences?.length,finalText:report.finalText,error:report.error}));
}
