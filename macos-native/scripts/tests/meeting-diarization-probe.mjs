// Test-only Pi extension: fictional audio in memory, provider speaker labels verbatim.
import {validateAudio,realtimeURL} from '../../WorkFollow/Resources/wf-meeting-audio.mjs';

export function pcmWav(pcm) {
  const header=Buffer.alloc(44);
  header.write('RIFF');header.writeUInt32LE(pcm.length+36,4);header.write('WAVE',8);
  header.write('fmt ',12);header.writeUInt32LE(16,16);header.writeUInt16LE(1,20);
  header.writeUInt16LE(1,22);header.writeUInt32LE(16000,24);header.writeUInt32LE(32000,28);
  header.writeUInt16LE(2,32);header.writeUInt16LE(16,34);header.write('data',36);
  header.writeUInt32LE(pcm.length,40);return Buffer.concat([header,pcm]);
}

export default function probe(pi) {
  pi.registerCommand('wf-meeting-diarization-probe',{description:'Synthetic-only speaker API probe',handler:async(args,ctx)=>{
    try {
      const input=JSON.parse(args);
      if(input.synthetic!==true)throw new Error('仅允许虚构合成音测试。');
      const pcm=validateAudio(input);
      const model=ctx.model;
      if(model?.id!=='qwen-audio-3.1-asr-flash')throw new Error('测试需要当前配置的 qwen-audio-3.1-asr-flash。');
      const auth=await ctx.modelRegistry.getApiKeyAndHeaders(model);
      if(!auth.ok||!auth.apiKey)throw new Error('Pi 模型认证未配置。');
      const url=new URL(realtimeURL(auth.baseUrl??model.baseUrl,model.id));
      url.protocol='https:';url.pathname='/api/v1/services/aigc/multimodal-generation/generation';url.search='';
      const started=performance.now();
      const response=await fetch(url,{method:'POST',signal:AbortSignal.timeout(90000),
        headers:{...auth.headers,Authorization:`Bearer ${auth.apiKey}`,'Content-Type':'application/json','X-DashScope-SSE':'disable'},
        body:JSON.stringify({model:model.id,input:{messages:[{role:'user',content:[{type:'input_audio',
          input_audio:{data:'data:audio/wav;base64,'+pcmWav(pcm).toString('base64')}}]}]},
          parameters:{format:'wav',sample_rate:'16000',speaker_diarization_enabled:true}})});
      const data=await response.json();
      if(!response.ok)throw new Error(`HTTP ${response.status}；错误码 ${String(data.code??'unknown').slice(0,100)}`);
      const sentences=(data.output?.sentences??[]).map(s=>({speaker_id:s.speaker_id??null,
        sentence_id:s.sentence_id,begin_time:s.begin_time,end_time:s.end_time,sentence_end:s.sentence_end,text:s.text}));
      ctx.ui.notify('WF_DIARIZATION_RESULT '+JSON.stringify({model:model.id,elapsedMs:Math.round(performance.now()-started),
        text:data.output?.text??'',sentences,outputKeys:Object.keys(data.output??{})}),'info');
    } catch(error) {
      const message=error.name==='TimeoutError'?'HTTP 转写超时。':error.message;
      ctx.ui.notify('WF_DIARIZATION_ERROR '+message,'error');
    }
  }});
}
