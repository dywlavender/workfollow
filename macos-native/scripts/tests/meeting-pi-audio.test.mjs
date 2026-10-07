import test from 'node:test';
import assert from 'node:assert/strict';
import {createRequire} from 'node:module';
import {mkdtemp, writeFile, rm, readdir} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {spawn} from 'node:child_process';
import {once} from 'node:events';
import extension, {validateAudio, realtimeURL, parseTranscript, runRealtime, meetingMinutesRules, audioModel}
  from '../../WorkFollow/Resources/wf-meeting-audio.mjs';

const moduleURL = new URL('../../WorkFollow/Resources/wf-meeting-audio.mjs', import.meta.url).href;
const pcm = Buffer.alloc(3200, 1);
const audio = {version: 2, format: 'pcm16', sampleRate: 16000, channels: 1,
  offset: 15, duration: 0.1, audio: pcm.toString('base64')};

test('memory protocol rejects paths, malformed audio and mismatched duration', () => {
  assert.deepEqual(validateAudio(audio), pcm);
  for (const overrides of [{file:'/tmp/audio'}, {audio:'not base64!'}, {duration:10}, {channels:2}, {version:1}]) {
    assert.throws(() => validateAudio({...audio, ...overrides}));
  }
  assert.equal(realtimeURL('https://test.cn-beijing.maas.aliyuncs.com/v1', 'configured-realtime'),
    'wss://test.cn-beijing.maas.aliyuncs.com/api-ws/v1/realtime?model=configured-realtime');
  assert.throws(() => realtimeURL('https://dashscope.aliyuncs.com', 'test'));
});

test('transcript schema preserves missing speaker and rejects invented timestamps', () => {
  assert.deepEqual(parseTranscript('{"version":1,"segments":[{"text":"发言","start":0}]}', 1).segments,
    [{text:'发言', start:0}]);
  assert.throws(() => parseTranscript('{"version":1,"segments":[{"text":"发言","start":5}]}', 1));
  assert.throws(() => parseTranscript('普通回答不是转写 JSON', 1));
});

test('Pi command returns actionable errors, not an empty success', async () => {
  const commands = new Map(), notices = [];
  extension({registerCommand:(name, command) => commands.set(name, command)}, {
    resolveAudioModel: async () => { throw new Error('Pi 音频模型认证未配置。'); }
  });
  await commands.get('wf-meeting-audio').handler(JSON.stringify(audio), {ui:{notify:(...args)=>notices.push(args)}});
  assert.deepEqual(notices, [['WF_MEETING_ERROR Pi 音频模型认证未配置。', 'error']]);
});

test('digital silence returns no speech without calling a model', async () => {
  const commands = new Map(), notices = [];
  extension({registerCommand:(name, command)=>commands.set(name,command)}, {
    resolveAudioModel: async ()=>assert.fail('Silence must not call a model')
  });
  await commands.get('wf-meeting-audio').handler(JSON.stringify({...audio,audio:Buffer.alloc(3200).toString('base64')}),
    {ui:{notify:(...args)=>notices.push(args)}});
  assert.equal(JSON.parse(notices[0][0].slice('WF_MEETING_RESULT '.length)).segments.length,0);
});

test('minutes reuse the single configured model through the realtime text channel', async () => {
  const expected = meetingMinutesRules();
  const commands=new Map(),notices=[];
  extension({registerCommand:(name,command)=>commands.set(name,command)}, {
    resolveAudioModel:async()=>({}),
    realtime:async input=>{
      assert.equal(input.instructions,expected);assert.equal(input.text,'fictional meeting data');return '# minutes';
    }
  });
  await commands.get('wf-meeting-minutes').handler(JSON.stringify({version:1,prompt:'fictional meeting data'}),{
    model:{id:'configured-realtime'},
    modelRegistry:{complete:async()=>assert.fail('Minutes must not fall back to chat-completions')},
    ui:{notify:(...args)=>notices.push(args)}
  });
  assert.deepEqual(notices,[['WF_MEETING_MINUTES # minutes','info']]);
});

test('audio model follows the configured Pi model instead of a hardcoded id', async () => {
  const asked=[];
  const connection=await audioModel({
    model:{id:'configured-realtime'},
    modelRegistry:{
      getAvailable:()=>assert.fail('Must not enumerate the registry for a hardcoded id'),
      getApiKeyAndHeaders:async model=>{
        asked.push(model.id);
        return {ok:true,apiKey:'synthetic-key',headers:{},baseUrl:'https://test.cn-beijing.maas.aliyuncs.com/v1'};
      }
    }
  });
  assert.deepEqual(asked,['configured-realtime']);
  assert.equal(connection.modelID,'configured-realtime');
  assert.equal(connection.url,'wss://test.cn-beijing.maas.aliyuncs.com/api-ws/v1/realtime?model=configured-realtime');
});

test('a missing Pi model is an actionable error, not a silent fallback', async () => {
  await assert.rejects(audioModel({modelRegistry:{getAvailable:()=>assert.fail('no hardcoded fallback')}}),
    /Pi 未选择模型/);
});

const require = createRequire('/opt/homebrew/lib/node_modules/@earendil-works/pi-coding-agent/package.json');
const {WebSocketServer} = require('ws');
const {WebSocket} = require('undici');
const factory = (url, options) => new WebSocket(url, options);

async function localServer(t, mode = 'success') {
  const server = new WebSocketServer({port:0, host:'127.0.0.1'});
  await once(server, 'listening');
  t.after(() => { for (const client of server.clients) client.terminate(); server.close(); });
  const received = [], bytes = [];
  server.on('connection', (socket, request) => {
    const events = [], connectionBytes = [];
    assert.equal(request.headers.authorization, 'Bearer synthetic-local-key');
    const reply = value => socket.send(JSON.stringify(value));
    reply({type:'session.created'});
    socket.on('message', data => {
      const event = JSON.parse(String(data)); received.push(event); events.push(event);
      if (event.type === 'session.update') {
        assert.deepEqual(event.session.modalities, ['text']);
        assert.equal(event.session.turn_detection, null);
        assert.equal(event.session.audio.input.format.sample_rate, 16000);
        if (mode === 'error') return reply({type:'error', error:{message:'DO_NOT_ECHO_SECRET'}});
        if (mode === 'close') return socket.close();
        if (mode !== 'timeout') reply({type:'session.updated'});
      } else if (event.type === 'input_audio_buffer.append') {
        const packet = Buffer.from(event.audio, 'base64'); bytes.push(packet); connectionBytes.push(packet);
      } else if (event.type === 'input_audio_buffer.commit') {
        assert.deepEqual(Buffer.concat(connectionBytes), pcm);
        reply({type:'input_audio_buffer.committed'});
      } else if (event.type === 'response.create') {
        const isAudio = events.some(e => e.type === 'input_audio_buffer.commit');
        const output = isAudio ? '{"version":1,"segments":[{"speaker":"讲话人1","text":"合成测试发言","start":0}]}' : '# 合成会议纪要';
        reply({type:'response.text.delta', delta:'ignore duplicate partial'});
        reply({type:'response.text.done', text:output});
        reply({type:'response.done', response:{status: mode === 'incomplete' ? 'incomplete' : 'completed', output:[]}});
      }
    });
  });
  return {url:`ws://127.0.0.1:${server.address().port}`, received, bytes};
}

test('real WebSocket preserves configure / commit / response order and final text', async t => {
  const server = await localServer(t);
  const output = await runRealtime({url:server.url, apiKey:'synthetic-local-key', pcm,
    instructions:'test', socketFactory:factory});
  assert.equal(parseTranscript(output, 0.1).segments[0].text, '合成测试发言');
  assert.deepEqual(server.received.map(e=>e.type),
    ['session.update','input_audio_buffer.append','input_audio_buffer.commit','response.create']);
});

for (const mode of ['error','close','timeout','incomplete']) {
  test(`socket ${mode} rejects instead of fabricating transcripts`, async t => {
    const server = await localServer(t, mode);
    await assert.rejects(runRealtime({url:server.url, apiKey:'synthetic-local-key', pcm,
      instructions:'test', socketFactory:factory, timeoutMs:mode==='timeout'?100:2000}),
    error => !error.message.includes('DO_NOT_ECHO_SECRET'));
  });
}

test('installed Pi loads actual extension: PCM + realtime minutes through local server only', async t => {
  const server = await localServer(t);
  const root = await mkdtemp(join(tmpdir(), 'wf-pi-adapter-'));
  t.after(()=>rm(root, {recursive:true, force:true}));
  const fixture = join(root, 'local-fixture.mjs');
  // Test wrapper injects local connection/auth only. Production resolves them from Pi.
  await writeFile(fixture, `import extension from ${JSON.stringify(moduleURL)};
    export default function(pi) {
      const wrapped = {registerCommand(name, command) {
        pi.registerCommand(name, {...command, handler:(args,ctx)=>command.handler(args,{...ctx,model:{id:'configured-realtime'}})});
      }};
      extension(wrapped, {resolveAudioModel:async()=>({url:${JSON.stringify(server.url)},apiKey:'synthetic-local-key'})});
    }`);
  const child = spawn('/opt/homebrew/bin/pi', ['--mode','rpc','--no-session','--no-tools','--no-extensions',
    '--no-skills','--no-prompt-templates','--no-context-files','--offline','--extension',fixture],
    {cwd:root, stdio:['pipe','pipe','pipe']});
  t.after(()=>child.kill());
  let buffer = '', notices = [], errors = '';
  child.stderr.on('data', data => { errors += String(data); });
  child.stdout.on('data', data => {
    buffer += String(data);
    let end;
    while ((end=buffer.indexOf('\n'))>=0) {
      const line = buffer.slice(0,end); buffer = buffer.slice(end+1);
      try { const event = JSON.parse(line); if(event.type==='extension_ui_request')notices.push(event); } catch {}
    }
  });
  async function prompt(message, prefix) {
    child.stdin.write(JSON.stringify({type:'prompt',id:'test',message})+'\n');
    const deadline = Date.now()+15000;
    while(Date.now()<deadline) {
      const result = notices.find(n=>n.message?.startsWith(prefix));
      if(result) return result.message.slice(prefix.length);
      if(notices.some(n=>n.notifyType==='error') || child.exitCode!=null) {
        assert.fail('Pi local transport failed: '+JSON.stringify(notices)+' '+errors);
      }
      await new Promise(resolve=>setTimeout(resolve,10));
    }
    assert.fail('Pi extension transport timed out');
  }
  const result = JSON.parse(await prompt('/wf-meeting-audio '+JSON.stringify(audio),'WF_MEETING_RESULT '));
  assert.equal(result.segments[0].text,'合成测试发言');
  assert.equal(result.segments[0].speaker,'片段 15.0s · 暂定讲话人1');
  assert.equal(await prompt('/wf-meeting-minutes '+JSON.stringify({version:1,prompt:'合成纪要数据'}),
    'WF_MEETING_MINUTES '),'# 合成会议纪要');
  assert.equal(await prompt('/wf-meeting-check','WF_MEETING_READY '),'connected');
  assert.deepEqual(await readdir(root), ['local-fixture.mjs']);
});
