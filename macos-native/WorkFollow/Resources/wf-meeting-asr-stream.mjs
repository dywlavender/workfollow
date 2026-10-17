// Dedicated ASR duplex protocol. Loaded inside Pi; PCM stays in memory.
import {createRequire} from 'node:module';
import {realpathSync} from 'node:fs';
import {randomUUID} from 'node:crypto';
import {validateAudio} from './wf-meeting-audio.mjs';

export class MeetingASRInputStream {
  constructor({url,apiKey,headers={},modelID,socketFactory,emit,offset=0,timeoutMs=20000,parameters={}}) {
    this.emit=emit;this.offset=offset;this.timeoutMs=timeoutMs;this.taskID=randomUUID();
    this.closed=false;this.stopping=false;this.lastSequence=-1;
    this.started=new Set();this.completed=new Set();this.pending=new Set();
    if(!socketFactory){
      const require=createRequire(realpathSync(process.argv[1]));
      const {WebSocket}=require('undici');socketFactory=(url,options)=>new WebSocket(url,options);
    }
    this.socket=socketFactory(url,{headers:{...headers,Authorization:`Bearer ${apiKey}`}});
    this.ready=new Promise((resolve,reject)=>{this.readyResolve=resolve;this.readyReject=reject;});
    this.timer=setTimeout(()=>this.fail('Pi 实时 ASR 连接超时。'),timeoutMs);
    this.socket.addEventListener('open',()=>this.sendCommand('run-task',{
      task_group:'audio',task:'asr',function:'recognition',model:modelID,
      parameters:{...parameters,format:'pcm',sample_rate:16000,heartbeat:true,
        max_sentence_silence:parameters.max_sentence_silence??800},input:{}
    }));
    this.socket.addEventListener('message',event=>{
      try{this.receive(JSON.parse(String(event.data)));}
      catch{this.fail('Pi 实时 ASR 返回无效事件。');}
    });
    this.socket.addEventListener('error',()=>this.fail('Pi 实时 ASR 连接失败，请检查模型、端点与认证。'));
    this.socket.addEventListener('close',()=>{if(!this.closed)this.fail('Pi 实时 ASR 连接中断。');});
  }
  sendCommand(action,payload){
    this.socket.send(JSON.stringify({header:{action,task_id:this.taskID,streaming:'duplex'},payload}));
  }
  receive(event){
    if(this.closed||event.header?.task_id!==this.taskID)return;
    const kind=event.header.event;
    if(kind==='task-failed'){
      const code=String(event.header.error_code??'unknown').replace(/[^\w.-]/g,'').slice(0,80);
      return this.fail(`Pi 实时 ASR 任务失败（${code}），请检查模型、认证与额度。`);
    }
    if(kind==='task-started'){
      clearTimeout(this.timer);this.readyResolve?.();this.readyResolve=null;this.readyReject=null;return;
    }
    if(kind==='task-finished'){
      if(!this.stopping)return this.fail('Pi 实时 ASR 任务提前结束。');
      if(this.pending.size)return this.fail('Pi 实时 ASR 已结束，但仍有语句未返回定稿。');
      clearTimeout(this.timer);this.closed=true;this.socket.close();this.finishResolve?.();return;
    }
    if(kind!=='result-generated')return;
    const sentence=event.payload?.output?.sentence;
    if(sentence?.heartbeat)return;
    if(!sentence||!Number.isInteger(sentence.sentence_id)||sentence.sentence_id<1||
       typeof sentence.text!=='string'||!Number.isFinite(sentence.begin_time)||sentence.begin_time<0||
       typeof sentence.sentence_end!=='boolean')return this.fail('Pi 实时 ASR 句子字段无效。');
    const itemID=`${this.taskID}:${sentence.sentence_id}`;
    if(this.completed.has(itemID))return;
    const offset=this.offset+sentence.begin_time/1000;
    if(!this.started.has(itemID)){
      this.started.add(itemID);this.pending.add(itemID);
      this.emit({kind:'speechStarted',itemID,offset});
    }
    if(sentence.sentence_end){
      if(!Number.isFinite(sentence.end_time)||sentence.end_time<sentence.begin_time)
        return this.fail('Pi 实时 ASR 定稿时间无效。');
      this.completed.add(itemID);this.pending.delete(itemID);
      this.emit({kind:'speechStopped',itemID,offset:this.offset+sentence.end_time/1000});
      this.emit({kind:'final',itemID,text:sentence.text,offset});
    }else{
      this.emit({kind:'preview',itemID,text:sentence.text,offset});
    }
  }
  async append(input){
    await this.ready;
    if(this.closed||this.stopping)throw new Error('Pi 实时 ASR 会话已停止。');
    const sequence=Number(input.sequence);
    if(Number.isFinite(sequence)&&sequence>=0){
      if(sequence<=this.lastSequence)return true;
      if(sequence!==this.lastSequence+1){
        this.fail(`Pi 实时 ASR sequence 缺口：期望 ${this.lastSequence+1}，收到 ${sequence}。`);
        throw new Error('Pi 实时 ASR sequence 缺口。');
      }
    }
    const pcm=validateAudio(input);
    if(this.socket.bufferedAmount>60*32000){
      this.fail('Pi 实时 ASR 音频发送积压。');throw new Error('Pi 实时 ASR 音频发送积压。');
    }
    try{
      // The server consumes raw binary PCM frames, not JSON/base64 audio events.
      for(let index=0;index<pcm.length;index+=3200)this.socket.send(pcm.subarray(index,index+3200));
    }catch{
      this.fail('Pi 实时 ASR 音频发送失败。');throw new Error('Pi 实时 ASR 音频发送失败。');
    }
    if(Number.isFinite(sequence)&&sequence>=0)this.lastSequence=sequence;
    return false;
  }
  async finish(){
    await this.ready;
    if(this.closed)throw new Error('Pi 实时 ASR 会话不可继续。');
    if(this.finishPromise)return this.finishPromise;
    this.stopping=true;
    this.finishPromise=new Promise((resolve,reject)=>{
      this.finishResolve=resolve;this.finishReject=reject;
      this.timer=setTimeout(()=>this.fail('Pi 实时 ASR 尾段转写超时。'),this.timeoutMs);
      this.sendCommand('finish-task',{input:{}});
    });
    return this.finishPromise;
  }
  fail(message){
    if(this.closed)return;
    this.closed=true;clearTimeout(this.timer);
    const error=new Error(message);this.readyReject?.(error);this.finishReject?.(error);
    this.emit({kind:'error',message});try{this.socket.close();}catch{}
  }
  cancel(){this.fail('Pi 实时 ASR 会话已取消。');}
}
