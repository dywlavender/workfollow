// HTTP ASR transport runs exclusively inside Pi; WAV exists only in memory.
export const httpASRModel='qwen-audio-3.1-asr-flash';
export function pcmWav(pcm) {
  const header=Buffer.alloc(44);
  header.write('RIFF');header.writeUInt32LE(pcm.length+36,4);header.write('WAVE',8);
  header.write('fmt ',12);header.writeUInt32LE(16,16);header.writeUInt16LE(1,20);
  header.writeUInt16LE(1,22);header.writeUInt32LE(16000,24);header.writeUInt32LE(32000,28);
  header.writeUInt16LE(2,32);header.writeUInt16LE(16,34);header.write('data',36);
  header.writeUInt32LE(pcm.length,40);return Buffer.concat([header,pcm]);
}

export function decodeHTTPTranscript(data,duration) {
  const output=data.output;
  if(!output||typeof output.text!=='string'||!Array.isArray(output.sentences))
    throw new Error('HTTP 转写未返回有效句子列表。');
  if(output.text.trim()&&!output.sentences.some(s=>typeof s.text==='string'&&s.text.trim()))
    throw new Error('HTTP 转写有文字但缺少句子，未静默丢弃结果。');
  const segments=output.sentences.map(s=>{
    if(typeof s.text!=='string'||!Number.isFinite(s.begin_time)||s.begin_time<0||s.begin_time/1000>duration||
       !Number.isFinite(s.end_time)||s.end_time<s.begin_time||s.end_time/1000>duration+0.25||s.sentence_end!==true||
       (s.speaker_id!=null&&(!Number.isInteger(s.speaker_id)||s.speaker_id<0)))
      throw new Error('HTTP 转写句子或时间戳无效。');
    return {text:s.text,start:s.begin_time/1000,...(s.speaker_id!=null?{speaker:`讲话人${s.speaker_id+1}`}:{})};
  }).filter(s=>s.text.trim());
  return {version:1,segments};
}

export async function transcribeHTTP({url,apiKey,headers={},modelID,pcm,timeoutMs=90000,fetchImpl=fetch}) {
  if(modelID!==httpASRModel)throw new Error('当前模型不支持此 HTTP 转写适配。');
  let response;
  try {
    response=await fetchImpl(url,{method:'POST',signal:AbortSignal.timeout(timeoutMs),
      headers:{...headers,Authorization:`Bearer ${apiKey}`,'Content-Type':'application/json','X-DashScope-SSE':'disable'},
      body:JSON.stringify({model:modelID,input:{messages:[{role:'user',content:[{type:'input_audio',
        input_audio:{data:'data:audio/wav;base64,'+pcmWav(pcm).toString('base64')}}]}]},
        parameters:{format:'wav',sample_rate:'16000',speaker_diarization_enabled:true}})});
  } catch(error) {
    throw new Error(error.name==='TimeoutError'?'Pi HTTP 转写超时。':'Pi HTTP 转写连接失败，请检查网络与端点。');
  }
  let data;
  try { data=await response.json(); } catch { throw new Error('Pi HTTP 转写响应不是有效 JSON。'); }
  if(!response.ok||data.code)throw new Error(`Pi HTTP 转写失败（HTTP ${response.status}，${String(data.code??'unknown').replace(/[^\w.-]/g,'').slice(0,80)}）。请检查模型、认证与额度。`);
  return decodeHTTPTranscript(data,pcm.length/32000);
}
