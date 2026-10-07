// Explicit real-service probe via Pi. No audio, transcript or credential output.
import {spawn} from 'node:child_process';
import {fileURLToPath} from 'node:url';
const extension = fileURLToPath(new URL('../WorkFollow/Resources/wf-meeting-audio.mjs', import.meta.url));
// 2026-10-06 起扩展不再内置模型 id：用 WF_MEETING_MODEL 或位置参数指定实时模型，
// 未指定则沿用 Pi 当前模型（它必须是百炼业务空间的实时模型）。
const model = process.env.WF_MEETING_MODEL ?? process.argv.slice(2).find(a => !a.startsWith('--')) ?? '';
const args = ['--mode','rpc','--no-session','--no-tools','--no-extensions',
  '--no-skills','--no-prompt-templates','--no-context-files','--offline','--extension',extension];
if (model) args.push('--model', model);
const pi = spawn('/opt/homebrew/bin/pi', args,
  {cwd:'/private/tmp',stdio:['pipe','pipe','ignore']});
const synthetic = process.argv.includes('--synthetic');
let buffer='', done=false, phase='check';
const timer=setTimeout(()=>finish('Pi 连接检查超时。',1),synthetic ? 110000 : 25000);
function prompt(message) { pi.stdin.write(JSON.stringify({type:'prompt',id:'meeting-'+phase,message})+'\n'); }
function finish(message,code) {
  if(done)return; done=true;clearTimeout(timer);pi.kill();console.log(message);process.exitCode=code;
}
pi.on('error',()=>finish('无法启动 Pi。',1));
pi.on('exit',()=>{if(!done)finish('Pi 提前退出。',1);});
pi.stdout.on('data',data=>{
  buffer+=String(data);let end;
  while((end=buffer.indexOf('\n'))>=0){
    const line=buffer.slice(0,end);buffer=buffer.slice(end+1);
    let event;try{event=JSON.parse(line);}catch{continue;}
    if(event.type==='extension_ui_request' && event.message?.startsWith('WF_MEETING_READY ')){
      if (!synthetic) finish('Pi → 内置会议扩展 → Qwen 会话连接与配置成功；未发送音频。',0);
      else {
        console.log('Pi 会话配置成功；接下来仅发送 1 秒合成测试音，不使用麦克风。');
        const tone=Buffer.alloc(32000);
        for(let i=0;i<16000;i++)tone.writeInt16LE(Math.round(Math.sin(i*2*Math.PI*440/16000)*3000),i*2);
        phase='audio'; prompt('/wf-meeting-audio '+JSON.stringify({version:2,format:'pcm16',sampleRate:16000,
          channels:1,offset:0,duration:1,audio:tone.toString('base64')}));
      }
    }else if(event.type==='extension_ui_request' && event.message?.startsWith('WF_MEETING_RESULT ')){
      const value=JSON.parse(event.message.slice('WF_MEETING_RESULT '.length));
      if(value.version!==1 || !Array.isArray(value.segments))return finish('转写协议无效。',1);
      console.log('合成测试音经 Pi/Qwen 完成协议请求；这不是语音识别质量验收。');
      phase='minutes';prompt('/wf-meeting-minutes '+JSON.stringify({version:1,
        prompt:'以下是合成测试会议数据，不是真实会议。已有纪要：无。新增确认发言：A 提议下周交付，B 明确交付期限改为周五，A 确认。请只输出 Markdown 会议纪要，期限采用周五，不猜负责人。'}));
    }else if(event.type==='extension_ui_request' && event.message?.startsWith('WF_MEETING_MINUTES ')){
      const text=event.message.slice('WF_MEETING_MINUTES '.length);
      if(!text.trim() || !text.includes('周五'))return finish('合成纪要未保留明确期限。',1);
      finish('Pi → 内置扩展 → Qwen 音频与纪要请求成功；纪要包含确认期限，未使用真实录音。',0);
    }else if(event.type==='extension_ui_request' && event.message?.startsWith('WF_MEETING_ERROR ')){
      finish(event.message.slice('WF_MEETING_ERROR '.length),1);
    }else if(event.type==='extension_error' || (event.type==='response'&&event.success===false)){
      finish('Pi 扩展加载或命令执行失败。',1);
    }
  }
});
prompt('/wf-meeting-check');
