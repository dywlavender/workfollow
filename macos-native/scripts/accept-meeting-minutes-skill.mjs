// Fictional text only; all model traffic remains in Pi. No audio or microphone.
import {spawn} from 'node:child_process';
import {fileURLToPath} from 'node:url';
import {writeFile} from 'node:fs/promises';
const extension=process.env.MEETING_TEST_EXTENSION || fileURLToPath(new URL('../WorkFollow/Resources/wf-meeting-audio.mjs',import.meta.url));
const skill=fileURLToPath(new URL('../../.pi/skills/meeting-minutes/SKILL.md',import.meta.url));
const child=spawn('/opt/homebrew/bin/pi',['--mode','rpc','--no-session','--no-tools','--no-extensions',
  '--no-skills','--skill',skill,'--no-prompt-templates','--no-context-files','--offline','--extension',extension],
  {cwd:'/private/tmp',stdio:['pipe','pipe','ignore']});
let buffer='',pending;
function settle(error,value){if(!pending)return;const p=pending;pending=null;clearTimeout(p.timer);error?p.reject(error):p.resolve(value);}
child.on('error',()=>settle(new Error('无法启动 Pi。')));
child.on('exit',()=>settle(new Error('Pi 提前退出。')));
child.stdout.on('data',data=>{
  buffer+=String(data);let end;
  while((end=buffer.indexOf('\n'))>=0){
    const line=buffer.slice(0,end);buffer=buffer.slice(end+1);let event;
    try{event=JSON.parse(line);}catch{continue;}
    if(event.type==='extension_ui_request'&&event.message?.startsWith('WF_MEETING_MINUTES '))settle(null,event.message.slice('WF_MEETING_MINUTES '.length));
    else if(event.type==='extension_ui_request'&&event.message?.startsWith('WF_MEETING_ERROR '))settle(new Error(event.message.slice('WF_MEETING_ERROR '.length)));
    else if(event.type==='extension_error'||(event.type==='response'&&event.success===false))settle(new Error('Pi skill 扩展加载或执行失败。'));
  }
});
function minutes(previous,transcript){return new Promise((resolve,reject)=>{
  pending={resolve,reject,timer:setTimeout(()=>settle(new Error('Pi 纪要验收超时。')),90000)};
  child.stdin.write(JSON.stringify({type:'prompt',message:'/wf-meeting-minutes '+JSON.stringify({version:1,
    prompt:JSON.stringify({previousMinutes:previous,newTranscript:transcript})})})+'\n');
});}
const rounds=[
  [{speaker:'片段0 · 暂定讲话人1',text:'我提议周五交付，预算三千元。'},
   {speaker:'片段0 · 暂定讲话人2',text:'同意周五交付，预算三千元。'}],
  [{speaker:'片段10 · 暂定讲话人1',text:'交付期限改为下周一，预算改为两千五百元，大家确认吗？'},
   {speaker:'片段10 · 暂定讲话人2',text:'确认这两项修改。请小李整理清单，期限下周一。'}],
  [{speaker:'片段20 · 暂定讲话人1',text:'还需要校对方案，负责人和期限暂时没定。'},
   {speaker:'片段20 · 暂定讲话人2',text:'我提议另外购买投影仪，尚未决定。'}]
];
const report={kind:'Pi-meeting-minutes-skill-trial',createdAt:new Date().toISOString(),syntheticText:true,audioSent:false,
  skill:'.pi/skills/meeting-minutes/SKILL.md',loading:'production extension loads skill as system instructions',rounds:[]};
try{
  let previous='暂无';
  for(let i=0;i<rounds.length;i++){
    const start=performance.now();const output=await minutes(previous,rounds[i]);
    report.rounds.push({input:rounds[i],minutes:output,latencyMs:Math.round(performance.now()-start)});
    previous=output;console.log('纪要第 '+(i+1)+' 轮完成。');
  }
}catch(error){report.error=error.message;console.error(error.message);process.exitCode=1;}
finally{
  child.kill();
  if(process.argv[2])await writeFile(process.argv[2],JSON.stringify(report,null,2)+'\n');
}
