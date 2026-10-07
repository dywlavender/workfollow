import test from 'node:test';
import assert from 'node:assert/strict';
import extension,{audioModel} from '../../WorkFollow/Resources/wf-meeting-audio.mjs';
import {httpASRModel,pcmWav,decodeHTTPTranscript,transcribeHTTP} from '../../WorkFollow/Resources/wf-meeting-http.mjs';

const pcm=Buffer.alloc(32000,1);
const response={output:{text:'你好',sentences:[{text:'你好',begin_time:100,end_time:900,sentence_end:true,speaker_id:0}]}};
test('Pi HTTP sends memory WAV and requests diarization',async()=>{
  const result=await transcribeHTTP({url:'https://test',apiKey:'test-only',modelID:httpASRModel,pcm,
    fetchImpl:async(url,options)=>{
      assert.equal(options.headers.Authorization,'Bearer test-only');
      const body=JSON.parse(options.body);
      assert.equal(body.parameters.speaker_diarization_enabled,true);
      const wav=Buffer.from(body.input.messages[0].content[0].input_audio.data.split(',')[1],'base64');
      assert.equal(wav.toString('ascii',0,4),'RIFF');
      assert.equal(wav.readUInt32LE(24),16000);
      assert.deepEqual(wav.subarray(44),pcm);
      return {ok:true,json:async()=>response};
    }});
  assert.deepEqual(result,{version:1,segments:[{text:'你好',start:0.1,speaker:'讲话人1'}]});
  assert.equal(pcmWav(pcm).length,32044);
});
test('missing sentences and failed service responses are errors, not empty success',async()=>{
  assert.throws(()=>decodeHTTPTranscript({output:{text:'你好',sentences:[]}},1));
  await assert.rejects(transcribeHTTP({url:'https://test',apiKey:'test-only',modelID:httpASRModel,pcm,
    fetchImpl:async()=>({ok:false,status:401,json:async()=>({code:'InvalidApiKey'})})}),/HTTP 401/);
});
test('model registry selects HTTP without changing selected model',async()=>{
  const connection=await audioModel({model:{id:httpASRModel},modelRegistry:{getApiKeyAndHeaders:async()=>({
    ok:true,apiKey:'test-only',baseUrl:'https://test.cn-beijing.maas.aliyuncs.com/v1'})}});
  assert.equal(connection.transport,'http');
  assert.equal(connection.modelID,httpASRModel);
  assert.equal(connection.url,'https://test.cn-beijing.maas.aliyuncs.com/api/v1/services/aigc/multimodal-generation/generation');
});
test('HTTP commands bypass WebSocket and preserve local speaker scope; ASR minutes fail clearly',async()=>{
  const commands=new Map(),notices=[];
  extension({registerCommand:(name,c)=>commands.set(name,c)},{
    resolveAudioModel:async()=>({transport:'http'}),realtime:()=>assert.fail('must not use WebSocket'),
    http:async()=>decodeHTTPTranscript(response,1)});
  const ctx={ui:{notify:m=>notices.push(m)}};
  await commands.get('wf-meeting-check').handler('',ctx);
  assert.equal(notices.pop(),'WF_MEETING_READY http-configured');
  await commands.get('wf-meeting-audio').handler(JSON.stringify({version:2,format:'pcm16',sampleRate:16000,
    channels:1,offset:20,duration:1,audio:pcm.toString('base64')}),ctx);
  assert.equal(JSON.parse(notices.pop().slice('WF_MEETING_RESULT '.length)).segments[0].speaker,'片段 20.0s · 讲话人1');
  await commands.get('wf-meeting-minutes').handler(JSON.stringify({version:1,prompt:'生成纪要'}),ctx);
  assert.match(notices.pop(),/^WF_MEETING_ERROR 当前 ASR 模型/);
});
