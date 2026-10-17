// Read normalized ASR WAV without converting or changing the stored samples.
export function readMeetingWav(wav){
  if(wav.toString('ascii',0,4)!=='RIFF'||wav.toString('ascii',8,12)!=='WAVE')
    throw new Error('请使用会议保存的 -asr.wav 文件。');
  let format,pcm;
  for(let offset=12;offset+8<=wav.length;){
    const type=wav.toString('ascii',offset,offset+4),length=wav.readUInt32LE(offset+4);
    const start=offset+8,end=start+length;
    if(end>wav.length)throw new Error('WAV 音频文件尚未写完。');
    if(type==='fmt ')format=wav.subarray(start,end);
    if(type==='data')pcm=wav.subarray(start,end);
    offset=end+(length%2);
  }
  if(!format||format.length<16||format.readUInt16LE(0)!==1||format.readUInt16LE(2)!==1||
     format.readUInt32LE(4)!==16000||format.readUInt16LE(14)!==16||!pcm?.length||pcm.length%2)
    throw new Error('复测需要单声道、16kHz、PCM16 的会议 WAV。');
  return {pcm,duration:pcm.length/32000};
}
