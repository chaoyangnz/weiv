#!/usr/bin/env node
import { execFileSync } from 'node:child_process';
import { createHash } from 'node:crypto';
import { existsSync, mkdirSync, mkdtempSync, readFileSync, readdirSync, writeFileSync, copyFileSync, rmSync, renameSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join, resolve } from 'node:path';
const root = resolve(import.meta.dirname, '..');
const project = root.endsWith('/weiv') ? 'weiv' : 'neiv';
let state = join(root, 'dist/release/state');
let artifacts = join(root, 'dist/release/artifacts');
let sink = join(root, 'dist/release/sink');
const verb = process.argv[2] || 'status';
const args = process.argv.slice(3);
const allowDirty = args.includes('--allow-dirty');
const preflightOnly = args.includes('--preflight-only');
const run = (cmd, a, opts={}) => (execFileSync(cmd, a, {cwd:root, encoding:'utf8', stdio:opts.stdio||'pipe', env:{...process.env, npm_config_offline:'true', npm_config_audit:'false'}, ...opts}) || '').trim();
const read = name => JSON.parse(readFileSync(join(state, name+'.json')));
const write = (name, value) => { mkdirSync(state,{recursive:true}); writeFileSync(join(state,name+'.json'), JSON.stringify(value,null,2)+'\n'); };
const sha = p => createHash('sha256').update(readFileSync(p)).digest('hex');
const files = project==='weiv' ? ['packages/weiv/package.json','packages/weiv-darwin-arm64/package.json'] : ['packages/neiv/package.json'];
function preflight() {
  for (const tool of ['git','node','npm','tar']) run('which',[tool]);
  const versions=files.map(f=>JSON.parse(readFileSync(join(root,f))).version);
  if(project==='weiv') {
    run('which',['bun']);
    if(!preflightOnly) {
      try { run('which',['cyna']); }
      catch { throw Error('Missing Cyna toolchain: install the pinned release before verify'); }
      try { run('node',['--input-type=module','-e',"import.meta.resolve('vite')"]); }
      catch { throw Error('Missing Vite test dependency: run npm ci before release verify'); }
    }
    const p=JSON.parse(readFileSync(join(root,files[0])));
    versions.push(p.optionalDependencies['@weivjs/weiv-darwin-arm64']);
    if(!existsSync(join(root,'packages/weiv-darwin-arm64/bin/weiv'))) throw Error('Missing committed platform binary: packages/weiv-darwin-arm64/bin/weiv');
    const kind=run('file',['packages/weiv-darwin-arm64/bin/weiv']);
    if(!kind.includes('Mach-O 64-bit arm64')) throw Error('Committed platform binary is not Mach-O arm64');
  } else {
    if(!preflightOnly) run('which',['cyna']);
    const manifest=readFileSync(join(root,'cyna.toml'),'utf8').match(/^version = "([^"]+)"/m)?.[1];
    versions.push(manifest);
    const script=readFileSync(join(root,'packages/neiv/scripts/ensure-cyna-package.sh'),'utf8');
    const artifact=script.match(/artifact="\$sdk\/cyna-dist\/packages\/neiv\/([^"/]+)"/)?.[1];
    versions.push(artifact);
    const lock=JSON.parse(readFileSync(join(root,'packages/neiv/package-lock.json')));
    versions.push(lock.version,lock.packages[''].version);
    const dep=JSON.parse(readFileSync(join(root,files[0]))).dependencies.weivjs;
    if(!dep) throw Error('Neiv npm dependency weivjs is missing');
    if(!preflightOnly && !existsSync(join(root,'packages/neiv/node_modules/typescript')) && !existsSync(join(root,'node_modules/typescript'))) throw Error('Generated frontend input missing: install locked TypeScript dependencies before verify');
  }
  if(new Set(versions).size!==1) throw Error(`Version disagreement: ${versions.join(', ')}. Align declared version sources before release.`);
  const version=versions[0];
  const requested=args.find(x=>x.startsWith('--version='))?.split('=')[1];
  if(requested && requested!==version) throw Error(`Requested ${requested}, sources say ${version}`);
  const commit=run('git',['rev-parse','HEAD']);
  if(!allowDirty && run('git',['status','--porcelain'])) throw Error('Working tree is dirty');
  const tag='v'+version;
  const existingTag=run('git',['tag','--list',tag]);
  if(existingTag && !allowDirty) throw Error(`Tag ${tag} already exists`);
  return {project,version,tag,commit,targets:[process.platform+'-'+process.arch],artifacts:files.map(f=>JSON.parse(readFileSync(join(root,f))).name),gates:project==='weiv'?['committed-binary','component-runtime-suite','cyna-suite','package-release-check','package-smoke','vite-plugin','staged-package-smoke']:['proof-app-build','cyna-package','frontend-package'],sink:'local'};
}
function plan(){ const p=preflight(); if(!preflightOnly){for(const name of ['verify','publish','published'])rmSync(join(state,name+'.json'),{force:true});write('plan',p);} console.log(JSON.stringify(p,null,2)); console.log(preflightOnly?'preflight passed':'next: release verify'); }
function assertPlan(){const p=read('plan'); if(run('git',['rev-parse','HEAD'])!==p.commit) throw Error('Plan is stale: commit changed'); return p;}
function verify(){const p=assertPlan();for(const name of ['verify','publish','published'])rmSync(join(state,name+'.json'),{force:true});mkdirSync(artifacts,{recursive:true}); const packages=project==='weiv'?['packages/weiv-darwin-arm64','packages/weiv']:['packages/neiv']; const outputs=[];
  if(project==='weiv') {
    const legacy=join(root,'cyna-out/bin/weiv'),backup=join(root,'cyna-out/bin/weiv.release-backup');
    mkdirSync(join(root,'cyna-out/bin'),{recursive:true});
    if(existsSync(backup))throw Error('Previous binary backup exists: '+backup);
    const hadLegacy=existsSync(legacy);if(hadLegacy)renameSync(legacy,backup);
    try {
      copyFileSync(join(root,'packages/weiv-darwin-arm64/bin/weiv'),legacy);
      run('bun',['test','test/component','test/runtime','test/ui-core','test/inspect'],{stdio:'inherit'});
      run('cyna',['test','.'],{stdio:'inherit'});
      run('npm',['run','pkg:release-check'],{stdio:'inherit'});
      run('npm',['run','pkg:smoke'],{stdio:'inherit'});
      run('node',['test/package/vite-plugin.test.mjs'],{stdio:'inherit',env:{...process.env,WEIV_BINARY_PATH:join(root,'packages/weiv-darwin-arm64/bin/weiv')}});
    } finally {rmSync(legacy,{force:true});if(hadLegacy)renameSync(backup,legacy);}
  }
  else run('sh',['build.sh'],{stdio:'inherit'});
  for(const pkg of packages){
    if(project==='neiv') run('sh',['packages/neiv/scripts/ensure-cyna-package.sh'],{stdio:'inherit'});
    if(project==='weiv' && pkg==='packages/weiv') {run('node',['packages/weiv/scripts/build.mjs'],{stdio:'inherit'});run('node',['packages/weiv/scripts/generate-types.mjs'],{stdio:'inherit'});}
    if(project==='neiv') run('node',['packages/neiv/scripts/build-frontend.mjs'],{stdio:'inherit'});
    const output=JSON.parse(run('npm',['pack','--json','--ignore-scripts','--pack-destination',artifacts,'./'+pkg]))[0];
    outputs.push({name:output.filename,sha256:sha(join(artifacts,output.filename))});
  }
  for(const item of outputs){const target=join(artifacts,item.name);run('tar',['-tzf',target]);}
  const main = outputs.at(-1);
  const unpack = join(root,'dist/release/smoke'); rmSync(unpack,{recursive:true,force:true});mkdirSync(unpack,{recursive:true});
  run('tar',['-xzf',join(artifacts,main.name),'-C',unpack]);
  if(project==='weiv') {
    run('node',['--input-type=module','-e',"import('./dist/release/smoke/package/dist/vite.mjs'); import('./dist/release/smoke/package/dist/bun.mjs')"]);
    const consumer=mkdtempSync(join(tmpdir(),'weiv-release-consumer-'));
    try {
      run('npm',['install','--offline','--ignore-scripts','--omit=optional','--no-save',join(artifacts,main.name)],{cwd:consumer});
      run('node',['--input-type=module','-e',"await import('weivjs/vite'); await import('weivjs/bun')"],{cwd:consumer});
    } finally {rmSync(consumer,{recursive:true,force:true});}
    run('node',[join(unpack,'package/bin/weiv.mjs'),'--help'],{stdio:'inherit',env:{...process.env,WEIV_BINARY_PATH:join(root,'packages/weiv-darwin-arm64/bin/weiv')}});
  } else {
    run('node',['--input-type=module','-e',"globalThis.window={addEventListener(){}}; await import('./dist/release/smoke/package/dist/sdk.js'); await import('./dist/release/smoke/package/dist/slots.js')"]);
    if(!existsSync(join(unpack,'package/cyna-dist/packages/neiv/'+p.version+'/manifest.toml'))) throw Error('Packed Cyna package is missing');
  }
  writeFileSync(join(artifacts,'SHA256SUMS'),outputs.map(x=>`${x.sha256}  ${x.name}`).join('\n')+'\n');
  write('verify',{...p,outputs,gates:p.gates.map(name=>({name,result:'passed'}))}); console.log('verified:',outputs);console.log('next: release publish --sink=local');
}
function verified(){const p=assertPlan(),v=read('verify');if(v.commit!==p.commit||v.version!==p.version)throw Error('Verify state is stale');for(const gate of p.gates||[])if(!v.gates?.some(g=>g.name===gate&&g.result==='passed'))throw Error('Required gate did not pass: '+gate);if(!v.outputs?.length)throw Error('Verify state has no artifacts');for(const o of v.outputs)if(sha(join(artifacts,o.name))!==o.sha256)throw Error('Verified artifact changed: '+o.name);return {p,v};}
function publish(){const {p,v}=verified();if(!args.includes('--sink=local'))throw Error('Only offline local sink is implemented; public publishing is not wired');rmSync(join(state,'published.json'),{force:true});mkdirSync(sink,{recursive:true});for(const o of v.outputs){const src=join(artifacts,o.name),dst=join(sink,o.name);if(existsSync(dst)&&sha(dst)!==o.sha256)rmSync(dst);copyFileSync(src,dst);}copyFileSync(join(artifacts,'SHA256SUMS'),join(sink,'SHA256SUMS'));write('publish',{commit:p.commit,sink:'local',outputs:v.outputs});console.log('next: release verify-published');}
function tag(){const {p}=verified();if(run('git',['status','--porcelain']))throw Error('Tag requires a clean tree');const existing=run('git',['tag','--list',p.tag]);if(existing){if(run('git',['rev-list','-n','1',p.tag])!==p.commit)throw Error('Existing tag points at another commit');console.log('tag already matches verified commit');return;}run('git',['tag','-a',p.tag,'-m',p.tag,p.commit]);console.log('created local annotated tag '+p.tag);}
function smokeLocalSink(p,x){
  const mainName=project==='weiv'?`weivjs-${p.version}.tgz`:`neiv-${p.version}.tgz`;
  const main=x.outputs.find(o=>o.name===mainName);
  if(!main)throw Error('Local sink main package missing: '+mainName);
  const smoke=mkdtempSync(join(tmpdir(),`${project}-release-smoke-`));
  try {
  if(project==='weiv'){
    run('npm',['install','--offline','--ignore-scripts','--omit=optional','--no-save',join(sink,main.name)],{cwd:smoke});
    run('node',['--input-type=module','-e',"await import('weivjs/vite'); await import('weivjs/bun')"],{cwd:smoke});
  } else {
    run('tar',['-xzf',join(sink,main.name),'-C',smoke]);
    if(!existsSync(join(smoke,`package/cyna-dist/packages/neiv/${p.version}/manifest.toml`)))throw Error('Local sink Cyna package missing');
    run('node',['--input-type=module','-e',"globalThis.window={addEventListener(){}}; await import('./package/dist/sdk.js'); await import('./package/dist/slots.js')"],{cwd:smoke});
  }
  } finally {rmSync(smoke,{recursive:true,force:true});}
}
function published(){const p=assertPlan(),x=read('publish');if(x.commit!==p.commit)throw Error('Publish state is stale');rmSync(join(state,'published.json'),{force:true});for(const o of x.outputs)if(sha(join(sink,o.name))!==o.sha256)throw Error('Published hash mismatch: '+o.name);smokeLocalSink(p,x);write('published',{commit:p.commit,sink:'local',outputs:x.outputs});console.log('next: release record');}
function sinkSelfTest(){
  const source=artifacts,prior=[state,artifacts,sink],temp=mkdtempSync(join(tmpdir(),`${project}-release-sink-`));
  try{
    state=join(temp,'state');artifacts=join(temp,'artifacts');sink=join(temp,'sink');mkdirSync(artifacts,{recursive:true});
    const version=JSON.parse(readFileSync(join(root,files[0]))).version;
    const names=readdirSync(source).filter(n=>n.endsWith('.tgz')&&n.includes(version));
    if(!names.length)throw Error('No packed release tarballs to exercise the local sink');
    const outputs=names.map(name=>{copyFileSync(join(source,name),join(artifacts,name));return {name,sha256:sha(join(artifacts,name))};});
    writeFileSync(join(artifacts,'SHA256SUMS'),outputs.map(o=>`${o.sha256}  ${o.name}`).join('\n')+'\n');
    const commit=run('git',['rev-parse','HEAD']);write('plan',{project,version,tag:'v'+version,commit,gates:['sink-self-test']});
    write('verify',{project,version,commit,outputs,gates:[{name:'sink-self-test',result:'passed'}]});
    args.push('--sink=local');publish();published();record();
    const tampered=join(sink,outputs[0].name),original=readFileSync(tampered);
    writeFileSync(tampered,Buffer.concat([original,Buffer.from('tampered')]));
    let rejected=false;try{published();}catch(error){if(!String(error.message).includes('Published hash mismatch'))throw error;rejected=true;}
    if(!rejected)throw Error('Local sink accepted a changed artifact');
    console.log('local sink self-test passed with '+outputs.length+' packed artifact(s)');
  } finally {[state,artifacts,sink]=prior;rmSync(temp,{recursive:true,force:true});}
}
function record(){const p=assertPlan(),v=read('verify'),x=read('published');if(v.commit!==p.commit||x.commit!==p.commit)throw Error('Release state is stale');const body=`# ${project} ${p.tag} rehearsal\n\n- Commit: ${p.commit}\n- Sink: local\n- Gates: ${v.gates.map(g=>g.name+' '+g.result).join(', ')}\n- Artifacts:\n${v.outputs.map(o=>`  - ${o.name}: ${o.sha256}`).join('\n')}\n`;writeFileSync(join(state,'record.md'),body);console.log(join(state,'record.md'));}
try{if(verb==='plan')plan();else if(verb==='verify')verify();else if(verb==='tag')tag();else if(verb==='publish')publish();else if(verb==='verify-published')published();else if(verb==='record')record();else if(verb==='sink-self-test')sinkSelfTest();else if(verb==='rehearse'){plan();verify();args.push('--sink=local');publish();published();record();}else if(verb==='status')console.log('release plan | verify | tag | publish --sink=local | verify-published | record | rehearse | sink-self-test');else throw Error('Unknown verb: '+verb);}catch(e){console.error('release '+verb+': '+e.message);process.exitCode=1;}
