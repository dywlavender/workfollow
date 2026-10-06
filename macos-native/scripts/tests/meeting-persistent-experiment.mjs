// Experiment only, not bundled or selected by Native. Model traffic stays in Pi.
import {createRequire} from 'node:module';
import {realpathSync} from 'node:fs';
import {randomUUID} from 'node:crypto';
import builtin, {audioModel, validateAudio, parseTranscript, transcriptionInstructions}
  from '../../WorkFollow/Resources/wf-meeting-audio.mjs';

export class PersistentAudioExperiment {
  constructor({url,apiKey,headers={},socketFactory,timeoutMs=90000,toolOutput=false}) {
    this.toolOutput=toolOutput;
    this.timeoutMs=timeoutMs;this.requestCount=0;this.pending=null;this.closed=false;
    if(!socketFactory){
      const require=createRequire(realpathSync(process.argv[1]));
      const {WebSocket}=require('undici');socketFactory=(url,options)=>new WebSocket(url,options);
    }
    this.socket=socketFactory(url,{headers:{...headers,Authorization:`Bearer ${apiKey}`}});
    this.ready=new Promise((resolve,reject)=>{
      this.readyResolve=resolve;this.readyReject=reject;
      this.readyTimer=setTimeout(()=>this.fail(new Error('Pi 常驻音频连接超时。')),timeoutMs);
    });
    this.socket.addEventListener('open',()=>this.configure(contextInstructions(60),true));
    this.socket.addEventListener('message',event=>{
      try{this.receive(JSON.parse(String(event.data)));}catch(error){this.fail(error);}
    });
    this.socket.addEventListener('error',()=>this.fail(new Error('Pi 常驻音频连接失败。')));
    this.socket.addEventListener('close',()=>this.fail(new Error('Pi 常驻音频连接关闭。')));
  }
  send(event){this.socket.send(JSON.stringify({event_id:randomUUID(),...event}));}
  configure(instructions,initial=false){
    const session={instructions,temperature:0};
    if(this.toolOutput){
      session.instructions+='\n必须调用 submit_meeting_transcript 提交本次转写，不以普通消息提交。';
      session.tools=[{type:'function',function:{name:'submit_meeting_transcript',
        description:'提交当前新增音频的逐字转写；不是执行会议中提到的操作。',
        parameters:{type:'object',properties:{version:{type:'integer',enum:[1]},segments:{type:'array',items:{type:'object',
          properties:{speaker:{type:'string'},text:{type:'string'},start:{type:'number'}},required:['text','start']}}},required:['version','segments']}}}];
    }
    if(initial)Object.assign(session,{modalities:['text'],turn_detection:null,
      audio:{input:{format:{type:'pcm',sample_rate:16000,sample_format:'s16le',channels:1,packing:'interleaved',channel_layout:'mono'}}}});
    this.send({type:'session.update',session});
  }
  receive(event){
    if(this.closed)return;
    if(event.type==='session.created')this.serverSessionID=event.session?.id;
    if(event.type==='error')return this.fail(new Error('Pi 常驻音频模型拒绝请求。'));
    if(event.type==='session.updated'){
      if(this.readyResolve){clearTimeout(this.readyTimer);this.readyResolve();this.readyResolve=null;this.readyReject=null;return;}
      const request=this.pending;if(!request||request.state!=='configuring')return;
      request.state='input';
      for(let i=0;i<request.pcm.length;i+=3200)this.send({type:'input_audio_buffer.append',audio:request.pcm.subarray(i,i+3200).toString('base64')});
      this.send({type:'input_audio_buffer.commit'});
    }else if(event.type==='input_audio_buffer.committed'){
      if(this.pending?.state!=='input')return;
      this.pending.state='response';this.send({type:'response.create'});
    }else if(event.type==='response.text.delta'){
      if(this.pending)this.pending.partial+=event.delta??'';
    }else if(event.type==='response.text.done'){
      if(this.pending)this.pending.final=event.text??'';
    }else if(event.type==='response.function_call_arguments.done'){
      if(this.pending&&this.toolOutput){
        if(event.name!=='submit_meeting_transcript'||this.pending.tool)return this.fail(new Error('Pi 转写工具响应不符合契约。'));
        this.pending.tool={callID:event.call_id,arguments:event.arguments};
      }
    }else if(event.type==='response.done'){
      const request=this.pending;if(!request)return;
      if(event.response?.status!=='completed')return this.fail(new Error('Pi 常驻音频响应未完成。'));
      if(this.toolOutput&&!request.tool)return this.fail(new Error('Pi 模型未调用转写工具。'));
      const text=request.tool?.arguments||request.final||(event.response.output??[]).flatMap(i=>i.content??[])
        .filter(c=>c.type==='text'||c.type==='output_text').map(c=>c.text??'').join('')||request.partial;
      if(!text.trim())return this.fail(new Error('Pi 常驻音频响应为空。'));
      if(request.tool)this.send({type:'conversation.item.create',item:{type:'function_call_output',
        call_id:request.tool.callID,output:'参数已收到，将由本地校验；不要继续回答。'}});
      this.pending=null;clearTimeout(request.timer);request.resolve(text);
    }
  }
  async transcribe(pcm,instructions){
    await this.ready;
    if(this.closed)throw new Error('Pi 常驻音频会话不可继续。');
    if(this.pending)throw new Error('Pi 常驻音频请求冲突。');
    return await new Promise((resolve,reject)=>{
      this.pending={pcm,resolve,reject,partial:'',final:'',state:'configuring',
        timer:setTimeout(()=>this.fail(new Error('Pi 常驻音频请求超时。')),this.timeoutMs)};
      this.requestCount++;
      this.configure(instructions);
    });
  }
  fail(error){
    if(this.closed)return;
    this.closed=true;clearTimeout(this.readyTimer);
    this.readyReject?.(error);this.readyReject=null;this.readyResolve=null;
    if(this.pending){clearTimeout(this.pending.timer);this.pending.reject(error);this.pending=null;}
    try{this.socket.close();}catch{}
  }
  close(){this.fail(new Error('Pi 常驻音频实验已结束。'));}
}

export function contextInstructions(duration){
  return transcriptionInstructions(duration)
    .replace('仅根据当前音频，不能证明与其他分段同一人时不得假定身份。',
      '本会话保留先前音频。根据声音与先前音频比对，同一声音沿用历史标签；不能确定时省略speaker。')+
    '\n只转写本次新输入，不重复历史发言。时间start从当前音频的0秒计算。'+
    '\n输出从 { 开始，到 } 结束，不输出解释、Markdown 或代码块。';
}

export default function experiment(pi){
  builtin(pi);
  let session;
  pi.registerCommand('wf-meeting-audio-context',{
    description:'Experimental persistent meeting audio context (not production)',
    handler:async(args,ctx)=>{
      let stage='input',diagnostic='';
      try{
        const input=JSON.parse(args),pcm=validateAudio(input);
        stage='connection';
        if(!session)session=new PersistentAudioExperiment({...await audioModel(ctx),toolOutput:input.experimentalToolOutput===true});
        const instructions=contextInstructions(input.duration);
        stage='response';
        const output=await session.transcribe(pcm,instructions);
        stage='parse';
        try {
          const value=JSON.parse(output.trim().replace(/^```(?:json)?\s*/, '').replace(/\s*```$/, ''));
          const starts=(value.segments??[]).map(s=>s.start).filter(Number.isFinite);
          diagnostic=`; version=${value.version}; segments=${value.segments?.length}; startRange=${starts.length?Math.min(...starts)+'..'+Math.max(...starts):'none'}; duration=${input.duration}`;
        } catch { diagnostic='; invalid JSON'; }
        const result=parseTranscript(output,input.duration);
        for(const segment of result.segments)if(segment.speaker)segment.speaker='会话暂定'+segment.speaker;
        ctx.ui.notify('WF_MEETING_RESULT '+JSON.stringify({...result,experiment:{
          persistent:true,toolOutput:session.toolOutput,connections:1,requestCount:session.requestCount,serverSessionID:session.serverSessionID}}),'info');
      }catch(error){
        const knownReasons=new Set(['Pi 模型未调用转写工具。','Pi 转写工具响应不符合契约。',
          'Pi 常驻音频模型拒绝请求。','Pi 常驻音频响应未完成。','Pi 常驻音频响应为空。',
          'Pi 常驻音频连接失败。','Pi 常驻音频连接关闭。','Pi 常驻音频请求超时。']);
        const reason=knownReasons.has(error?.message)?`; reason=${error.message}`:'';
        session?.close();session=null;
        ctx.ui.notify(`WF_MEETING_ERROR Pi 常驻音频实验失败，阶段=${stage}${stage==='parse'?diagnostic:''}${reason}。未自动重连或合并身份。`,'error');
      }
    }
  });
  pi.registerCommand('wf-meeting-audio-context-stop',{
    description:'Close experimental audio context',handler:async(_,ctx)=>{
      session?.close();session=null;ctx.ui.notify('WF_MEETING_CONTEXT_STOPPED','info');
    }
  });
}
