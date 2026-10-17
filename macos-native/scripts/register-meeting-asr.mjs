// Add the dedicated ASR model to an existing Pi provider without changing auth.
import {readFile,writeFile,rename,stat} from 'node:fs/promises';
import {homedir} from 'node:os';
import {join} from 'node:path';
const modelID='qwen-audio-3.1-asr-flash-streaming';
const providerFlag=process.argv.indexOf('--provider');
const providerName=providerFlag>=0?process.argv[providerFlag+1]:undefined;
const path=join(process.env.PI_CODING_AGENT_DIR||join(homedir(),'.pi','agent'),'models.json');
const config=JSON.parse(await readFile(path,'utf8'));
const candidates=Object.entries(config.providers??{}).filter(([name,provider])=>
  providerName?name===providerName:provider.models?.some(model=>model.id==='qwen-audio-3.1-asr-flash'));
if(candidates.length!==1)throw new Error('请选择一个已配置百炼认证的 Pi provider，使用 --provider <名称>。');
const [name,provider]=candidates[0];
if(!provider.models?.some(model=>model.id===modelID)){
  if(!process.argv.includes('--apply')){
    console.log(JSON.stringify({provider:name,model:modelID,status:'ready; pass --apply to register'}));
  }else{
    provider.models=[...(provider.models??[]),{id:modelID,name:modelID}];
    const mode=(await stat(path)).mode&0o777;
    const temporary=path+'.meeting-tmp';
    await writeFile(temporary,JSON.stringify(config,null,2)+'\n',{mode});
    await rename(temporary,path);
    console.log(JSON.stringify({provider:name,model:modelID,status:'registered'}));
  }
}else console.log(JSON.stringify({provider:name,model:modelID,status:'already registered'}));
