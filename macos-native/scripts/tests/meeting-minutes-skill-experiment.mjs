// Trial only: explicitly load the skill inside Pi before the existing minutes handler.
import {readFileSync} from 'node:fs';
import builtin from '../../WorkFollow/Resources/wf-meeting-audio.mjs';
const source=readFileSync(new URL('../../../.pi/skills/meeting-minutes/SKILL.md',import.meta.url),'utf8');
const rules=source.replace(/^---\n[\s\S]*?\n---\n/,'').trim();
export default function experiment(pi){
  builtin({registerCommand(name,definition){
    if(name!=='wf-meeting-minutes')return pi.registerCommand(name,definition);
    pi.registerCommand(name,{...definition,handler:async(args,ctx)=>{
      const input=JSON.parse(args);
      await definition.handler(JSON.stringify({...input,prompt:rules+'\n\n以下是输入数据：\n'+input.prompt}),ctx);
    }});
  }});
}
