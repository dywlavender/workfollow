// Synthetic acceptance only. Observe TEXT output; no microphone or PCM logging.
import builtin, {runRealtime} from '../../WorkFollow/Resources/wf-meeting-audio.mjs';
export default function diagnostic(pi) {
  let currentContext;
  builtin({registerCommand(name,definition){
    pi.registerCommand(name,{...definition,handler:async(args,ctx)=>{
      currentContext=ctx;
      try { return await definition.handler(args,ctx); } finally { currentContext=null; }
    }});
  }},{realtime:async input=>{
    const text=await runRealtime(input);
    if(input.pcm)currentContext?.ui.notify('WF_MEETING_SYNTHETIC_OUTPUT '+text,'info');
    return text;
  }});
}
