// Synthetic A/B/A/B probe through Pi only. No audio files or real microphone.
import {spawn} from 'node:child_process';
import {fileURLToPath} from 'node:url';
import {writeFile} from 'node:fs/promises';
const expected=[
  {speaker:'A',voice:'Tingting',text:'今天讨论项目交付。我建议下周五提交方案，预算暂定三千元。'},
  {speaker:'B',voice:'Eddy',text:'周五来不及，我建议改为下周一，预算改成两千五百元。'},
  {speaker:'A',voice:'Tingting',text:'同意，下周一提交，预算两千五百元。请小李整理清单。'},
  {speaker:'B',voice:'Eddy',text:'确认，我负责校对，小李整理清单，截止日期都是下周一。'}];
if(process.argv.includes('--reverse'))expected.reverse();
const model=process.env.WF_MEETING_MODEL;
const production=process.argv.includes('--production');
if(!model)throw new Error('请通过 WF_MEETING_MODEL 指定当前会议模型。');
const report={kind:'Pi-HTTP-speaker-diarization-probe',model,synthetic:true,audioSaved:false,
  liveMicrophoneTest:false,continuousStreamingTest:false,expected};
let child;
try {
  const fixture=spawn('/private/tmp/wf-meeting-speech-fixture',[],{stdio:['pipe','pipe','ignore']});
  const parts=[];fixture.stdout.on('data',b=>parts.push(b));fixture.stdin.end(JSON.stringify(expected));
  await new Promise((resolve,reject)=>{fixture.on('error',reject);fixture.on('exit',c=>c===0?resolve():reject(new Error('合成失败')));});
  const voices=JSON.parse(Buffer.concat(parts).toString());
  let offset=0;
  report.voiceRanges=voices.map((line,i)=>{const audio=Buffer.from(line.audio,'base64');
    const range={speaker:expected[i].speaker,start:offset,end:offset+audio.length/32000};offset=range.end+0.75;return range;});
  const pcm=Buffer.concat(voices.flatMap(l=>[Buffer.from(l.audio,'base64'),Buffer.alloc(24000)]));
  report.duration=pcm.length/32000;
  child=spawn('/opt/homebrew/bin/pi',['--mode','rpc','--no-session','--no-tools','--no-extensions','--no-skills',
    '--no-prompt-templates','--no-context-files','--offline','--model',model,'--extension',
    process.env.WF_MEETING_EXTENSION??fileURLToPath(new URL(production?'../WorkFollow/Resources/wf-meeting-audio.mjs':'./tests/meeting-diarization-probe.mjs',import.meta.url))],{cwd:'/private/tmp',stdio:['pipe','pipe','ignore']});
  report.productionExtension=production;
  const began=Date.now();
  const result=await new Promise((resolve,reject)=>{
    let buffer='';const timer=setTimeout(()=>reject(new Error('Pi 测试超时。')),100000);
    const done=(error,value)=>{clearTimeout(timer);error?reject(error):resolve(value);};
    child.on('error',()=>done(new Error('Pi 启动失败。')));child.on('exit',()=>done(new Error('Pi 提前退出。')));
    child.stdout.on('data',chunk=>{buffer+=String(chunk);let end;
      while((end=buffer.indexOf('\n'))>=0){const line=buffer.slice(0,end);buffer=buffer.slice(end+1);let event;
        try{event=JSON.parse(line);}catch{continue;}const message=event.message??'';
        if(message.startsWith('WF_DIARIZATION_RESULT '))done(null,JSON.parse(message.slice('WF_DIARIZATION_RESULT '.length)));
        else if(production&&message.startsWith('WF_MEETING_RESULT ')){
          const value=JSON.parse(message.slice('WF_MEETING_RESULT '.length));
          done(null,{elapsedMs:Date.now()-began,text:value.segments.map(s=>s.text).join(''),
            sentences:value.segments.map((s,i)=>({text:s.text,begin_time:s.start*1000,
              end_time:(value.segments[i+1]?.start??report.duration)*1000,
              speaker_id:s.speaker??null}))});
        }
        else if(message.startsWith('WF_MEETING_ERROR '))done(new Error(message.slice('WF_MEETING_ERROR '.length)));
        else if(message.startsWith('WF_DIARIZATION_ERROR '))done(new Error(message.slice('WF_DIARIZATION_ERROR '.length)));
        else if(event.type==='extension_error')done(new Error('Pi 扩展失败。'));
      }});
    child.stdin.write(JSON.stringify({type:'prompt',message:(production?'/wf-meeting-audio ':'/wf-meeting-diarization-probe ')+JSON.stringify({synthetic:true,
      version:2,format:'pcm16',sampleRate:16000,channels:1,offset:0,duration:pcm.length/32000,audio:pcm.toString('base64')})})+'\n');
  });
  report.result=result;
  report.turnLabels=report.voiceRanges.map(range=>{
    const overlap=s=>Math.max(0,Math.min(range.end,s.end_time/1000)-Math.max(range.start,s.begin_time/1000));
    const segments=result.sentences.filter(s=>overlap(s)>0).sort((a,b)=>overlap(b)-overlap(a));
    return {expectedSpeaker:range.speaker,providerLabel:segments[0]?.speaker_id??null,
      overlappingLabels:[...new Set(segments.map(s=>s.speaker_id))]};
  });
  const labels=report.turnLabels.map(t=>t.providerLabel);
  const normalize=t=>t.replace(/两千五百/g,'2500').replace(/三千/g,'3000').replace(/[\p{P}\p{Z}\s]/gu,'');
  report.checks={speakerLabelsReturned:labels.every(x=>x!==null),
    exactlyTwoSpeakers:new Set(result.sentences.map(s=>s.speaker_id).filter(x=>x!==null)).size===2,
    alternatingIdentityStable:labels.every(x=>x!==null)&&labels[0]===labels[2]&&labels[1]===labels[3]&&labels[0]!==labels[1],
    transcriptMatchesFixture:normalize(result.text)===normalize(expected.map(x=>x.text).join(''))};
  console.log(JSON.stringify({elapsedMs:result.elapsedMs,text:result.text,turnLabels:report.turnLabels,checks:report.checks}));
  if(!Object.values(report.checks).every(Boolean))process.exitCode=1;
} catch(error){report.error=error.message;console.error(error.message);process.exitCode=1;}
finally {child?.kill();const path=process.argv.slice(2).find(x=>!x.startsWith('--'));
  if(path)await writeFile(path,JSON.stringify(report,null,2)+'\n');}
