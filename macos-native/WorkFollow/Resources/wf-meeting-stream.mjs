// Persistent INPUT transcription inside Pi. Native owns only PCM and RPC pipes.
import {createRequire} from 'node:module';
import {realpathSync} from 'node:fs';
import {randomUUID} from 'node:crypto';
import {audioModel,validateAudio} from './wf-meeting-audio.mjs';

// 语义化常量（MEETING-AUDIO-002）：停止时补的静音必须**长于** VAD 静音门限，
// 否则最后一句话可能因 VAD 未闭合而丢失（旧实现补 700ms < 门限 800ms）。
// 测试锁死 finishSilenceMs > vadSilenceDurationMs，改 VAD 参数不会再次失配。
export const finishSilenceMs = 1200;
export const vadSilenceDurationMs = 800;
export const bytesPerSecond = 32000;

export class MeetingInputStream {
  constructor({url,apiKey,headers={},modelID,socketFactory,emit,offset=0,timeoutMs=20000}) {
    this.emit=emit;this.offset=offset;this.timeoutMs=timeoutMs;
    this.starts=new Map();this.pending=new Set();this.completed=new Set();this.bytesSinceCommit=0;this.closed=false;
    // 幂等接收（MEETING-AUDIO-001）：sequence 由采集侧从 0 单调连续递增，
    // 所以高水位即可判重——迟到重发的旧包必然 <= 水位，直接 ACK 不再 append。
    // 这样 Native 才能安全重试：at-least-once 传输 + 幂等接收 = 不丢也不重。
    this.lastSequence=-1;
    if(!socketFactory){const require=createRequire(realpathSync(process.argv[1]));const {WebSocket}=require('undici');socketFactory=(u,o)=>new WebSocket(u,o);}
    this.socket=socketFactory(url,{headers:{...headers,Authorization:`Bearer ${apiKey}`}});
    this.ready=new Promise((resolve,reject)=>{this.readyResolve=resolve;this.readyReject=reject;});
    this.timer=setTimeout(()=>this.fail('Pi 流式转写连接超时。'),timeoutMs);
    this.socket.addEventListener('open',()=>this.send({type:'session.update',session:{
      modalities:['text'],instructions:'只进行输入音频转写，不自行回答或调用工具。',
      // 转写与纪要共用同一个模型；ASR 子模型不再写死 qwen3-asr-flash-realtime。
      input_audio_transcription:{model:modelID},
      turn_detection:{type:'server_vad',threshold:0.2,prefix_padding_ms:500,silence_duration_ms:vadSilenceDurationMs,create_response:false,interrupt_response:false},
      audio:{input:{format:{type:'pcm',sample_rate:16000,sample_format:'s16le',channels:1,packing:'interleaved',channel_layout:'mono'}}}
    }}));
    this.socket.addEventListener('message',event=>{
      try{this.receive(JSON.parse(String(event.data)));}catch{this.fail('Pi 流式转写事件无效。');}
    });
    this.socket.addEventListener('error',()=>this.fail('Pi 流式转写连接失败。'));
    this.socket.addEventListener('close',()=>{if(!this.closed)this.fail('Pi 流式转写连接中断。');});
  }
  send(event){this.socket.send(JSON.stringify({event_id:randomUUID(),...event}));}
  receive(event){
    if(this.closed)return;
    if(event.type==='error'||event.type==='conversation.item.input_audio_transcription.failed'){
      const diagnostic={type:event.type,code:String(event.error?.code??'').slice(0,80),param:String(event.error?.param??'').slice(0,120),
        message:String(event.error?.message??'').slice(0,300)};
      this.emit({kind:'diagnostic',diagnostic});
      return this.fail('Pi 输入音频转写失败。');
    }
    if(event.type==='session.updated'){clearTimeout(this.timer);this.readyResolve?.();this.readyResolve=null;this.readyReject=null;return;}
    const id=event.item_id;
    if(event.type==='input_audio_buffer.speech_started'){
      this.activeItem=id;
      this.starts.set(id,this.offset+(event.audio_start_ms??0)/1000);this.pending.add(id);
      // VAD 生命周期（MEETING-AUDIO-002）：把讲话段的开始/结束原样交给 Native，
      // Native 的 turn 状态机据此检测"有讲话但没有 Final"。
      this.emit({kind:'speechStarted',itemID:id,text:null,offset:this.starts.get(id)??this.offset});
    }else if(event.type==='input_audio_buffer.speech_stopped'){
      if(this.activeItem===id)this.activeItem=null;
      this.emit({kind:'speechStopped',itemID:id,text:null,offset:this.offset+(event.audio_end_ms??0)/1000});
    }else if(event.type==='input_audio_buffer.committed'){
      this.bytesSinceCommit=0;
      if(!this.completed.has(id))this.pending.add(id);
    }else if(event.type==='conversation.item.input_audio_transcription.delta'){
      if(this.completed.has(id))return;
      this.pending.add(id);
      this.emit({kind:'preview',itemID:id,text:(event.text??'')+(event.stash??''),offset:this.starts.get(id)??this.offset});
    }else if(event.type==='conversation.item.input_audio_transcription.completed'){
      if(!this.completed.has(id)){
        this.completed.add(id);this.pending.delete(id);
        this.emit({kind:'final',itemID:id,text:event.transcript??'',offset:this.starts.get(id)??this.offset});
      }
    }
    this.tryFinish();
  }
  async append(input){
    await this.ready;
    if(this.closed||this.stopping)throw new Error('Pi 流式会话已停止。');
    let duplicate=false;
    const sequence=Number(input.sequence);
    if(Number.isFinite(sequence)&&sequence>=0){
      if(sequence<=this.lastSequence)duplicate=true;
      else if(sequence===this.lastSequence+1)this.lastSequence=sequence;
      else{
        // 序列完整性（验收修正）：不允许向前跳号——0→2 意味着中间必有丢失，
        // 显式失败而不是静默接受 2。串行 sender 下这是传输层 bug 的信号。
        this.fail(`Pi 流式 sequence 缺口：期望 ${this.lastSequence+1}，收到 ${sequence}。`);
        throw new Error('Pi 流式 sequence 缺口。');
      }
    }
    // sequence 缺省（旧调用方）退化为不去重，保持向后兼容。
    if(!duplicate){
      const pcm=validateAudio(input);
      if(this.socket.bufferedAmount>60*32000){this.fail('Pi 流式音频发送积压。');throw new Error('Pi 流式音频发送积压。');}
      this.bytesSinceCommit+=pcm.length;
      this.hasAudio=true;
      for(let i=0;i<pcm.length;i+=3200)this.send({type:'input_audio_buffer.append',audio:pcm.subarray(i,i+3200).toString('base64')});
    }
    return duplicate;
  }
  async finish(){
    await this.ready;
    if(this.closed)throw new Error('Pi 流式会话不可继续。');
    this.stopping=true;
    return await new Promise((resolve,reject)=>{
      this.finishResolve=resolve;this.finishReject=reject;
      this.timer=setTimeout(()=>this.fail('Pi 流式转写尾段超时。'),this.timeoutMs);
      // VAD may already have committed the last turn. A second manual commit
      // rejects an empty buffer. Supply end silence and await VAD/final events.
      // 尾静音按语义常量补足（> VAD 门限，见文件头说明），不再写死字节数。
      if(this.hasAudio)this.send({type:'input_audio_buffer.append',
        audio:Buffer.alloc(Math.ceil(finishSilenceMs/1000*bytesPerSecond)).toString('base64')});
      this.settleTimer=setTimeout(()=>{this.finishSettled=true;this.tryFinish();},this.hasAudio?1500:0);
    });
  }
  tryFinish(){
    if(this.stopping&&this.finishSettled&&!this.activeItem&&this.pending.size===0){
      clearTimeout(this.timer);this.closed=true;this.socket.close();this.finishResolve?.();
    }
  }
  fail(message){
    if(this.closed)return;
    this.closed=true;clearTimeout(this.timer);clearTimeout(this.settleTimer);
    const error=new Error(message);this.readyReject?.(error);this.finishReject?.(error);
    this.emit({kind:'error',message});try{this.socket.close();}catch{}
  }
  cancel(){this.fail('Pi 流式会话已取消。');}
}

export default function extension(pi){
  let stream;
  pi.registerCommand('wf-meeting-stream',{description:'Memory-only streaming input transcription',handler:async(args,ctx)=>{
    try{
      const input=JSON.parse(args);
      if(input.op==='start'){
        stream?.cancel();
        stream=new MeetingInputStream({...await audioModel(ctx),offset:input.offset??0,
          emit:event=>ctx.ui.notify('WF_MEETING_STREAM_EVENT '+JSON.stringify(event),event.kind==='error'?'error':'info')});
        await stream.ready;
      }else if(input.op==='append'){
        if(!stream)throw new Error();const duplicate=await stream.append(input);
        ctx.ui.notify('WF_MEETING_STREAM_ACK '+JSON.stringify({id:input.id,op:input.op,sequence:input.sequence,duplicate}),'info');
      }else if(input.op==='stop'){
        if(!stream)throw new Error();await stream.finish();stream=null;
      }else throw new Error();
      ctx.ui.notify('WF_MEETING_STREAM_ACK '+JSON.stringify({id:input.id,op:input.op}),'info');
    }catch{stream?.cancel();stream=null;ctx.ui.notify('WF_MEETING_ERROR Pi 流式转写命令失败。','error');}
  }});
}
