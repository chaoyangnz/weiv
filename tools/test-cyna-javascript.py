#!/usr/bin/env python3
"""Live Zig parity for JS primitives/imports/metadata/static modules, plus real DOM execution."""
import ast
import json
import os
from pathlib import Path
import re
import runpy
import shutil
import tempfile
import time
import sys

FLAT = "--flat" in sys.argv
STRUCTURAL = "--structural" in sys.argv
if STRUCTURAL and not FLAT:
    raise SystemExit("--structural requires --flat")

ROOT = Path(__file__).resolve().parents[1]
helpers = runpy.run_path(str(ROOT / 'tools/test-cyna-binding.py'))
run, literal, cyna_literal, ZIG_HEADER = (helpers[n] for n in ('run', 'literal', 'cyna_literal', 'ZIG_HEADER'))
HEADER = '''
import std.io;
import std.json;
import std.mem;
import { Value } from std.json;
import .compiler.sema.script_json as validation;
import { compile_report, take_unit } from .compiler.compile;
import { ComponentManifests, ComponentSlotManifest } from .compiler.sema.component_manifests;
import { build } from .compiler.backend.browser.build_component;
import { ImportOverride } from .compiler.backend.browser.emit.javascript_module;
import { JavaScriptError } from .compiler.backend.browser.emit.javascript_errors;
import { emit } from .compiler.backend.browser.emit.emit_static_module;
import { emit as emit_imports } from .compiler.backend.browser.emit.js_module.emit_module_imports;
import { emit as emit_metadata } from .compiler.backend.browser.emit.js_module.emit_tracked_metadata;
import { emit_html_string } from .compiler.backend.browser.emit.js_module.write_javascript;
fn expect_code(actual: string, expected: string): void {
    if actual != expected {
        const a = actual.bytes(); const b = expected.bytes(); var i: usize = 0;
        while i < a.len() and i < b.len() and a[i] == b[i] { i = i + 1; }
        io.write_line($"JavaScript mismatch at byte {i}");
        var end = i + 160; if end > a.len() { end = a.len(); }
        io.write_line(string.from(a[i..end]));
        end = i + 160; if end > b.len() { end = b.len(); }
        io.write_line(string.from(b[i..end]));
        assert(false);
    }
}
fn entity_dataset(payload: string): void {
    const data = json.parse(payload) catch (code) { panic("Expected entity cases"); };
    switch data {
        .array(records) => {
            var i: usize = 0;
            while i < records.items.len() {
                const item = &records.items[i];
                switch item {
                    .object(record) => {
                        const input = validation.text_field(&record, "input") catch (code) { panic("Expected input"); };
                        const output = validation.text_field(&record, "output") catch (code) { panic("Expected output"); };
                        var bytes = list<u8>(); emit_html_string(input, &bytes); expect_code(string.from(bytes.view()), output);
                    }
                    _ => { assert(false); }
                }
                i = i + 1;
            }
        }
        _ => { assert(false); }
    }
}
'''


def main():
    started = time.monotonic()
    header = HEADER
    if FLAT:
        header = header.replace("emit.emit_static_module", "emit.emit_module")
        header = "import { build as build_plan } from .compiler.backend.browser.emit.build_evaluator_plan;\nimport { emit as emit_static } from .compiler.backend.browser.emit.emit_static_module;\n" + header
    paths = run(['git', 'ls-files', '*.weiv']).stdout.splitlines()
    cases = [(p, (ROOT / p).read_bytes()) for p in paths]
    script = 'export interface Props {} export let props: Props; export const value=42;'
    templates = ['', 'hello &amp; &copy; &#x1F331;', '<p title="a &amp; b" disabled>Text</p><br>',
                 '<div style="color:red"><span>&NotEqualTilde;</span></div>',
                 '<svg><circle cx="1"/><foreignObject><div>HTML</div></foreignObject></svg>',
                 '<custom-element data-x="x"/>', '{{value}}', '<p bind:title="value"/>', '<p @click="value"/>',
                 '<p #if="value"/>', '<p #for="item in items"/>', '<Card/>', '<slot/>']
    scripts = [script] * len(templates)
    scripts[10] += ' export const items=[];'
    scripts[11] += ' export const Card={};'
    # Runtime case with a real script closure, props and event dispatch.
    templates += ['<section>owned</section>']
    scripts += ['export interface Props {title:string} export let props: Props; export const initial=props.title; export function save(){emit("saved",initial);}']
    templates += ['<p>imports</p>']
    scripts += ['import d, { n } from "./fixture.ts"; import * as ns from "./fixture.ts"; export interface Props {} export let props: Props; export const value=d+n+ns.extra;']
    if FLAT:
        templates += [
            '<p>{{props.title}}</p>',
            '<input class="base &amp;" bind:class="props.cls" bind:checked="props.flag" bind:value="props.value" bind:style="props.style" bind:aria-label="props.aria" bind:data-x="props.data"/>',
            '<button @click="emit(\'saved\', value)">{{value}}</button>',
            '<button @click="save">save</button>',
            '<p>{{({title: props.title}).title}}</p><p>{{[1,2].map(x => x + value).join(\",\")}}</p>',
            '<select bind:disabled="props.flag"><option bind:selected="props.flag">x</option></select>',
            '<p bind:class="props.cls" bind:style="props.style" bind:title="props.data">{{props.title ?? \"none\"}}</p>',
        ]
        scripts += ['export interface Props { [key:string]:any } export let props: Props; export let value=1; export function save(event){emit("saved",event.type);}'] * 7
        templates += ['<p #if="props.title">yes</p><p #else>no</p>']
        scripts += ['export interface Props {title:boolean} export let props: Props;']
        templates += ['<p #if="props.title" bind:title="value">{{value}}</p><p #else>{{props.alt}}</p>']
        scripts += ['export interface Props {title:boolean;alt:string} export let props: Props; export const value=42;']
        templates += ['<ul><li #for="item in props.items">{{item.label}}</li></ul>']
        scripts += ['export interface Props {items:{id:number;label:string}[]} export let props: Props;']
        templates += ['<button #for="item in props.items" :title="item.label" @click="emit(\'selected\', item.id)">{{item.label}}</button>']
        scripts += ['export interface Props {items:{id:number;label:string}[]} export let props: Props;']
        templates += ['<Card bind:title="props.title" @saved="emit(\'saved\', payload)"/>']
        scripts += ['import Card from "./child.weiv"; export interface Props {title:string} export let props: Props;']
        templates += ['<slot><p>{{props.title}}</p></slot>']
        scripts += ['export interface Props {title:string} export let props: Props;']
        templates += ['<Card><p>{{props.title}}</p></Card>']
        scripts += ['import Card from "./child.weiv"; export interface Props {title:string} export let props: Props;']
    cases += [(f'js-edge-{i}.weiv', ('<template>'+template+'</template><script lang="ts">'+source+'</script><style>p{color:red}</style>').encode()) for i, (template, source) in enumerate(zip(templates, scripts))]
    if STRUCTURAL and os.environ.get("WEIV_CYNA_CASE"):
        cases = [(label, source) for label, source in cases if label == os.environ["WEIV_CYNA_CASE"]]
        if not cases:
            raise SystemExit("No matching structural case")
    entities = ['&'+name+';' for name in re.findall(r'\.name = "([^"]+)"', (ROOT/'src/compiler/backend/browser/emit/js_module/html_entities.zig').read_text())]
    numeric = ['&#'+s+';' for s in ['0','65','128','255','55296','57343','1114111','1114112','2097151','2097152','-0','-1','+65','6_5','6__5','_65','65_','x41','X1F331','xD800','x110000','x200000','xZZ','x+41','x-0']]
    entity_inputs = entities + numeric + ['&amp;lt;', '&amp', '&unknown;', '&'+('a'*40)+';']
    temporary=[]
    stage=Path(tempfile.mkdtemp(prefix='.cyna-js-reference-',dir=ROOT))
    try:
        shutil.copytree(ROOT/'src',stage/'src')
        # Allocator spelling adaptation only; actual emitter functions stay intact.
        for path in (stage/'src').rglob('*.zig'):
            text=path.read_text()
            updated=re.sub(r'\.dupeZ\(u8, ([^\n)]+)\)',r'.dupeSentinel(u8, \1, 0)',text)
            if updated!=text:path.write_text(updated)
        zig=[ZIG_HEADER, r'''
const unit = @import("src/compiler/component_unit.zig");
const lowering = @import("src/compiler/lower/lower.zig");
const renderer = @import("src/compiler/backend/browser/render_tree/lower.zig");
const component = @import("src/compiler/backend/browser/component.zig");
const graph = @import("src/compiler/backend/browser/region_graph.zig");
const imports = @import("src/compiler/backend/browser/emit/js_module/imports.zig");
const metadata = @import("src/compiler/backend/browser/emit/js_module/tracked_metadata.zig");
const module = @import("src/compiler/backend/browser/emit/js_module.zig");
const output = @import("src/compiler/backend/browser/emit/js_module/output.zig");
const tree = @import("src/compiler/backend/browser/render_tree/tree.zig");
fn staticNodes(nodes: []const tree.Node) bool {
    for (nodes) |node| switch(node) {
        .text => {},
        .element => |value| { if(value.bind_effects.len>0 or value.event_effects.len>0 or !staticNodes(value.children)) return false; },
        else => return false,
    };
    return true;
}
''']
        if FLAT:
            zig[-1] = zig[-1].replace('.text => {},', '.text, .interpolation => {},').replace('value.bind_effects.len>0 or value.event_effects.len>0 or ', '')
        for i,(label,source) in enumerate(cases):
            zig.append(f'''test "JS {i}" {{
    var arena=std.heap.ArenaAllocator.init(std.testing.allocator); defer arena.deinit(); const allocator=arena.allocator();
    const source={literal(source)}; const sections=try parser.parseSfc(source);
    const raw=try parser.parseTemplate(sections.template.content,allocator); const normalized=try parser.normalizeTemplate(&raw,allocator);
    const payload=try analyze(sections.script.content,{literal(label.encode())},allocator); const decoded=try decoder.decode(payload,allocator);
    var catalog=Catalog{{.available=false,.manifest=.{{.entries=&.{{}}}}}}; var provider=slots.Provider{{.context=&catalog,.manifest_for=provide}};
    const bound=try binder.bind(&normalized,&decoded.facts,&provider,allocator);
    const lir=try lowering.lower(&normalized,&bound,allocator); const rendered=try renderer.lower(&lir,allocator);
    const model=unit.ComponentUnit{{.source_path={literal(label.encode())},.source=source,.sfc_document=sections,.template_document=raw,.normalized_template=normalized,.script=decoded.facts,.script_js=decoded.transpiled_code,.template_bindings=bound,.lir_document=lir}};
    const browser=component.BrowserComponent{{.unit=&model,.render_tree=rendered}};
    var overrides=std.ArrayList(module.ImportOverride).empty;
    for(model.script.imports,0..) |record,index| {{
        const target=try std.fmt.allocPrint(allocator,"./override-{i}-{{d}}.mjs",.{{index}});
        try overrides.append(allocator,.{{.source=record.source,.target=target}});
    }}
    var inventory=try graph.build(&model,&rendered,allocator);
    var meta=std.ArrayList(u8).empty; try metadata.emitTrackedStateGraphMetadata(&inventory,&meta,allocator);
    const preserved=try imports.buildPreservedImportsWithOverrides(&model,overrides.items,allocator);
    var evaluator_plan = @import("src/compiler/backend/browser/emit/js_module/cell_expressions.zig").Plan{{ .allocator=allocator, .script_names=try @import("src/compiler/lower/template_functions.zig").bindingNames(&model.script,allocator) }};
    _ = try evaluator_plan.nodes(rendered.nodes);
    const code: ?[]const u8=if({"true" if STRUCTURAL else "staticNodes(rendered.nodes)"}) try module.emitModuleWithSelection(&browser,&.{{}},overrides.items,&.{{}},&.{{}},allocator) else null;
    const encoded=try std.json.Stringify.valueAlloc(allocator,.{{.imports=preserved,.metadata=meta.items,.code=code,.evaluators=evaluator_plan.evaluators.items,.overrides=overrides.items}},.{{}});
    std.debug.print("\\nJSGOLD {i} {{s}}\\n",.{{encoded}});
}}''')
        zig.append('test "entity inventory" { var arena=std.heap.ArenaAllocator.init(std.testing.allocator); defer arena.deinit(); const allocator=arena.allocator(); const Case=struct{input:[]const u8,output:[]const u8}; var records=std.ArrayList(Case).empty; const inputs=[_][]const u8{'+','.join(literal(v.encode()) for v in entity_inputs)+'''};
    for(inputs) |input| { var bytes=std.ArrayList(u8).empty; try output.emitHtmlString(input,&bytes,allocator); try records.append(allocator,.{.input=input,.output=bytes.items}); }
    const encoded=try std.json.Stringify.valueAlloc(allocator,records.items,.{}); std.debug.print("\\nENTITIES {s}\\n",.{encoded});
}''')
        oracle_file=stage/'reference.zig';oracle_file.write_text('\n'.join(zig))
        oracle=run([os.environ.get('ZIG','zig'),'test',str(oracle_file),'--cache-dir',str(stage/'zig-cache'),'-L',str(ROOT/'libs/parser-backend/target/release'),'-lweiv_parser_backend','-liconv','-lc'])
        outcomes={int(i):json.loads(value) for i,value in re.findall(r'JSGOLD (\d+) ([^\n]+)',oracle.stderr)}
        dataset=json.loads(re.search(r'ENTITIES ([^\n]+)',oracle.stderr).group(1)); assert len(outcomes)==len(cases)
        if os.environ.get("WEIV_CYNA_ZIG_DUMP"):
            dump=Path(os.environ["WEIV_CYNA_ZIG_DUMP"]); dump.mkdir(parents=True, exist_ok=True)
            for i,(label,_) in enumerate(cases):
                code=outcomes[i]['code']
                (dump / f'{i:03d}-{re.sub(r"[^A-Za-z0-9_.-]", "_", label)}.zig.mjs').write_text(code if code is not None else '')
        case_sources=[]
        for i,(label,source) in enumerate(cases):
            result=outcomes[i]
            cy=[f'''test {cyna_literal(('JS corpus: '+label).encode())} {{
    const catalogs: ComponentManifests = {{ entries: list<ComponentSlotManifest>() }};
    var report=compile_report({cyna_literal(source)}, {cyna_literal(label.encode())}, &catalogs);
    const unit=take_unit(&report) catch(code) {{ panic("Expected unit"); }}; const browser=build(unit);
    var overrides=list<ImportOverride>();''']
            if FLAT:
                span = 'browser.unit.sfc_document.template.content_span'
                cy.append(f'    const span={span}; const source_bytes=browser.unit.source.bytes();')
                cy.append('    const plan=build_plan(source_bytes[span.start..span.end], &browser.render_tree, &browser.unit.script.facts) catch(code) { panic("Expected evaluator plan"); };')
            cy.append('    if plan.records.len()>0 { assert(plan.code.bytes().len()>0); } else { assert(plan.code.bytes().len()==0); }')
            for override in result['overrides']:
                cy.append(f'    overrides.push(ImportOverride {{ source: {cyna_literal(override["source"].encode())}, target: {cyna_literal(override["target"].encode())} }});')
            if result['imports']:
                cy.append('    assert(mem.contains(emit_imports(&browser.unit.script.facts, &overrides).bytes(), "from ".bytes()));')
            else:
                cy.append('    assert(emit_imports(&browser.unit.script.facts, &overrides).bytes().len()==0);')
            cy.append('    assert(mem.contains(emit_metadata(&browser.region_graph).bytes(), "trackedStateGraph".bytes()));')
            if result['code'] is None:
                cy.append('    const artifact=emit(&browser,&overrides) catch(code) { assert(code==JavaScriptError.unsupported_template); return; };')
                cy.append('    assert(artifact.code.bytes().len()>0);')
                cy.append(f'    const value: Value=.string(artifact.code); const encoded=json.encode(&value); io.write_line($"JSMODULE {i} {{encoded}}");')
            else:
                if STRUCTURAL:
                    cy.append(f'    const artifact=emit(&browser,&overrides) catch(code) {{ if code == JavaScriptError.unsupported_template {{ io.write_line("JSERROR {i} unsupported_template"); }} else if code == JavaScriptError.region_graph_mismatch {{ io.write_line("JSERROR {i} region_graph_mismatch"); }} else if code == JavaScriptError.evaluator_plan_mismatch {{ io.write_line("JSERROR {i} evaluator_plan_mismatch"); }} else {{ io.write_line("JSERROR {i} other"); }} return; }};')
                else:
                    cy.append('    const artifact=emit(&browser,&overrides) catch(code) { panic("Expected static module"); };')
                if FLAT and not STRUCTURAL and not result['evaluators']:
                    cy.append('    const static_artifact=emit_static(&browser,&overrides) catch(code) { panic("Expected static module"); }; assert(static_artifact.code.bytes().len()>0);')
                cy.append(f'    const value: Value=.string(artifact.code); const encoded=json.encode(&value); io.write_line($"JSMODULE {i} {{encoded}}");')
            cy.append('}');case_sources.append('\n'.join(cy))
        for start in range(0,len(dataset),160):
            case_sources.append(f'test "entity dataset {start}" {{ entity_dataset({cyna_literal(json.dumps(dataset[start:start+160],ensure_ascii=False).encode())}); }}')
        for start in range(0,len(case_sources),6):
            fd,name=tempfile.mkstemp(prefix=f'javascript_corpus_{start:03d}_',suffix='.test.cy',dir=ROOT/'cyna-port/src');os.close(fd);temporary.append(Path(name));Path(name).write_text(header+'\n'.join(case_sources[start:start+6]))
        checked=run([os.environ.get('CYNA','cyna'),'test',str(ROOT/'cyna-port'),'--jobs','2'])
        artifacts={int(i):json.loads(code) for i,code in re.findall(r'JSMODULE (\d+) ([^\n]+)',checked.stdout)}
        if STRUCTURAL:
            errors = re.findall(r'JSERROR (\d+) (\w+)', checked.stdout)
            if errors:
                print('Emission errors:', errors[:30])
            missing = [(i, label) for i, (label, _) in enumerate(cases)
                       if outcomes[i]['code'] is not None and i not in artifacts]
            mismatch = [(i, label, outcomes[i]['code'], artifacts[i]) for i, (label, _) in enumerate(cases)
                        if outcomes[i]['code'] is not None and i in artifacts and outcomes[i]['code'] != artifacts[i]]
            print(f'Structural differential: {len(artifacts) - len(mismatch)} exact modules, {len(mismatch)} byte mismatches, {len(missing)} unsupported or failed Cyna emissions')
            print('First unsupported:', missing[:8])
            import difflib
            report = Path(os.environ.get("WEIV_CYNA_DIFF_REPORT", "/tmp/weiv-cyna-structural-diffs.txt"))
            with report.open("w") as handle:
                for i, label, expected, actual in mismatch:
                    handle.write(f'=== byte mismatch {i} {label}\n')
                    for line in difflib.unified_diff(expected.splitlines(), actual.splitlines(), fromfile='zig', tofile='cyna', lineterm=''):
                        handle.write(line + '\n')
            print(f'Byte mismatch diffs written to {report} ({len(mismatch)} cases)')
            if os.environ.get("WEIV_CYNA_DUMP_DIR"):
                dump = Path(os.environ["WEIV_CYNA_DUMP_DIR"])
                dump.mkdir(parents=True, exist_ok=True)
                for i, label, expected, actual in mismatch:
                    stem = re.sub(r'[^A-Za-z0-9_.-]', '_', label)
                    (dump / f'{i:03d}-{stem}.zig.mjs').write_text(expected if expected is not None else '')
                    (dump / f'{i:03d}-{stem}.cyna.mjs').write_text(artifacts.get(i, ''))
                print(f'Full module dumps written to {dump}')
            return
        runtime_cases=[]
        offsets = [0,1,2,3,4,13,14] + ([9,10,12,15,16,17,18,19,20,21,22,23,24,25,26,27,28] if FLAT else [])
        for offset in offsets:
            index=len(paths)+offset; assert index in artifacts, 'Missing native emitted module'
            filename=stage/f'component-{offset}.mjs'; code=artifacts[index].replace('"weiv:cells"',json.dumps((ROOT/'packages/weiv/src/runtime/cell.ts').as_uri()))
            filename.write_text(code)
            for override in outcomes[index]['overrides']:
                if offset==28:
                    (stage/override['target']).write_text('''export function mountIntoBoundary(start,end,props={},handlers={},slots={}){let currentSlots=slots;const slot=currentSlots.default.mountIntoBoundary(start,end);return {setProps(){},setEventHandlers(){},setSlots(next){currentSlots=next;},update(){slot.update();},destroy(){slot.destroy();while(start.nextSibling!==end)start.nextSibling.remove();}};}\n''')
                elif offset==26:
                    (stage/override['target']).write_text('''export function mountIntoBoundary(start,end,props={},handlers={}){let currentProps=props,currentHandlers=handlers;const node=document.createElement('span');node.className='child';end.parentNode.insertBefore(node,end);const update=()=>{node.textContent=currentProps.title??'';};update();return {setProps(next){currentProps=next;},setEventHandlers(next){currentHandlers=next;},update,destroy(){node.remove();},emitSaved(value){currentHandlers.saved?.(value);}};}\n''')
                else:
                    (stage/override['target']).write_text('export default 10; export const n=20; export const extra=12;\n')
            runtime_cases.append({'file':str(filename),'index':offset})
        harness=stage/'runtime.mjs'
        harness.write_text('''import assert from "node:assert/strict";
import {JSDOM} from "jsdom";
import {pathToFileURL} from "node:url";
const cases='''+json.dumps(runtime_cases)+''';
for(const item of cases){
    const dom=new JSDOM('<main></main><aside></aside>'); globalThis.document=dom.window.document; globalThis.window=dom.window;
    const mod=await import(pathToFileURL(item.file).href); let saved=null;
    const root=document.querySelector('main'); const initialProps=(item.index===24||item.index===25)?{items:[{id:1,label:'one'},{id:2,label:'two'}]}:{title:'first'}; const handle=mod.mount(root,initialProps,{saved:value=>{saved=value;},selected:value=>{saved=value;}});
    assert.equal(handle.instance.destroyed,false); if(item.index!==10 && item.index!==24 && item.index!==25) assert.equal(handle.instance.refresh().props.title,'first');
    if(item.index!==26) for(const node of root.querySelectorAll('*')) assert.equal(node.getAttribute('data-weiv-scope'),mod.scopeId);
    if(item.index===0) assert.equal(root.textContent,'');
    if(item.index===1) assert.equal(root.textContent,'hello & © 🌱');
    if(item.index===2){ assert.equal(root.querySelector('p').getAttribute('title'),'a & b'); assert(root.querySelector('p').hasAttribute('disabled')); }
    if(item.index===3){assert.equal(root.querySelector('span').textContent,'≂̸');assert.equal(root.querySelector('div').style.color,'red');}
    if(item.index===4){assert.equal(root.querySelector('circle').namespaceURI,'http://www.w3.org/2000/svg');assert.equal(root.querySelector('div').namespaceURI,'http://www.w3.org/1999/xhtml');}
    if(item.index===13){handle.instance.refresh().save();assert.equal(saved,'first');handle.setProps({title:'next'});assert.equal(handle.instance.refresh().props.title,'next');assert.equal(handle.instance.refresh().initial,'first');handle.setEventHandlers({saved:value=>saved='updated:'+value});handle.instance.refresh().save();assert.equal(saved,'updated:first');}
    if(item.index===14) assert.equal(handle.instance.refresh().value,42);
    if(item.index===9) assert.equal(root.querySelectorAll('p').length,1);
    if(item.index===22){
        assert.equal(root.textContent,'yes');
        handle.setProps({title:false});handle.instance.updateDirty({bindings:['props'],paths:[]});
        assert.equal(root.textContent,'no');
        handle.setProps({title:true});handle.update();assert.equal(root.textContent,'yes');
    }
    if(item.index===23){
        assert.equal(root.textContent,'42');assert.equal(root.querySelector('p').title,'42');
        handle.setProps({title:false,alt:'other'});handle.instance.updateDirty({bindings:['props'],paths:[]});
        assert.equal(root.textContent,'other');
        handle.setProps({title:true,alt:'unused'});handle.update();
        assert.equal(root.textContent,'42');assert.equal(root.querySelector('p').title,'42');
    }
    if(item.index===24){
        const labels=()=>[...root.querySelectorAll('li')].map(node=>node.textContent);
        assert.deepEqual(labels(),['one','two']);
        handle.setProps({items:[{id:2,label:'TWO'},{id:1,label:'ONE'},{id:3,label:'three'}]});
        handle.instance.updateDirty({bindings:['props'],paths:[]});
        assert.deepEqual(labels(),['TWO','ONE','three']);
        handle.setProps({items:[{id:3,label:'THREE'}]});handle.update();
        assert.deepEqual(labels(),['THREE']);
    }
    if(item.index===25){
        let buttons=[...root.querySelectorAll('button')];
        assert.deepEqual(buttons.map(node=>node.title),['one','two']);
        buttons[0].dispatchEvent(new dom.window.Event('click'));assert.equal(saved,1);
        handle.setProps({items:[{id:2,label:'TWO'},{id:1,label:'ONE'}]});handle.update();
        buttons=[...root.querySelectorAll('button')];
        assert.deepEqual(buttons.map(node=>node.title),['TWO','ONE']);
        buttons[0].dispatchEvent(new dom.window.Event('click'));assert.equal(saved,2);
    }
    if(item.index===26){
        assert.equal(root.querySelector('.child').textContent,'first');
        handle.setProps({title:'second'});handle.instance.updateDirty({bindings:['props'],paths:[]});
        assert.equal(root.querySelector('.child').textContent,'second');
        handle.instance.refs.find(ref=>ref&&typeof ref.emitSaved==='function').emitSaved(7);
        assert.equal(saved,7);
        handle.destroy();assert.equal(root.querySelector('.child'),null);
    }
    if(item.index===27){
        assert.equal(root.textContent,'first');
        let slotUpdates=0,slotDestroys=0;
        const supplied={mountIntoBoundary(start,end){while(start.nextSibling!==end)start.nextSibling.remove();const node=document.createElement('strong');node.textContent='provided';end.parentNode.insertBefore(node,end);return {update(){slotUpdates++;},destroy(){slotDestroys++;node.remove();}};}};
        handle.setSlots({default:supplied});handle.update();
        assert.equal(root.textContent,'provided');
        handle.update();assert.equal(slotUpdates,1);
        handle.setSlots({});handle.update();assert.equal(slotDestroys,1);assert.equal(root.textContent,'first');
        handle.setProps({title:'next'});handle.instance.updateDirty({bindings:['props'],paths:[]});
        assert.equal(root.textContent,'next');
    }
    if(item.index===28){
        assert.equal(root.textContent,'first');
        handle.setProps({title:'next'});handle.instance.updateDirty({bindings:['props'],paths:[]});
        assert.equal(root.textContent,'next');
        handle.destroy();assert.equal(root.textContent,'');
    }
    if(item.index===15){
        handle.setProps({title:'changed'});handle.instance.updateDirty({bindings:['unrelated'],paths:[]});assert.equal(root.textContent,'first');handle.instance.updateDirty({bindings:['props'],paths:[]});assert.equal(root.textContent,'changed');await Promise.resolve();await Promise.resolve();assert.equal(root.textContent,'changed');
        handle.setProps({title:null}); handle.update(); assert.equal(root.textContent,'');
    }
    if(item.index===16){
        const input=root.querySelector('input');
        handle.setProps({cls:'extra',flag:true,value:42,style:'color:red',aria:false,data:true});handle.update();
        assert.equal(input.className,'base & extra');assert.equal(input.checked,true);assert.equal(input.value,'42');
        assert.equal(input.style.color,'red');assert.equal(input.getAttribute('aria-label'),'false');assert.equal(input.getAttribute('data-x'),'');
        handle.setProps({cls:false,flag:false,value:null,style:false,aria:null,data:false});handle.update();
        assert.equal(input.className,'base &');assert.equal(input.checked,false);assert.equal(input.value,'');
        assert.equal(input.hasAttribute('style'),false);assert.equal(input.hasAttribute('aria-label'),false);assert.equal(input.hasAttribute('data-x'),false);
        handle.setProps({cls:undefined,flag:0,value:0,style:true,aria:0,data:'next'});handle.update();assert.equal(input.getAttribute('aria-label'),'0');assert.equal(input.getAttribute('data-x'),'next');
    }
    if(item.index===17){assert.equal(root.textContent,'1');root.querySelector('button').dispatchEvent(new dom.window.Event('click'));handle.update();assert.equal(saved,1);assert.equal(root.textContent,'1');}
    if(item.index===18){root.querySelector('button').dispatchEvent(new dom.window.Event('click'));assert.equal(saved,'click');}
    if(item.index===19){assert.equal(root.querySelectorAll('p')[0].textContent,'first');assert.equal(root.querySelectorAll('p')[1].textContent,'2,3');}
    if(item.index===20){handle.setProps({flag:true});handle.update();assert.equal(root.querySelector('select').disabled,true);assert.equal(root.querySelector('option').selected,true);handle.setProps({flag:false});handle.update();assert.equal(root.querySelector('select').disabled,false);}
    if(item.index===21){handle.setProps({title:'changed',cls:true,style:null,data:false});handle.update();assert.equal(root.textContent,'changed');assert.equal(root.querySelector('p').getAttribute('class'),'');assert.equal(root.querySelector('p').hasAttribute('title'),false);}
    handle.setSlots({name:'retained'}); assert.equal(handle.instance.slots.name,'retained');
    const second=mod.mount(document.querySelector('aside'),{title:'second'});assert.equal(second.instance.refresh().props.title,'second');
    handle.destroy();assert.equal(handle.instance.destroyed,true);assert.equal(root.textContent,'');assert.equal(root.childNodes.length,2);assert.equal(second.instance.destroyed,false);second.destroy();
    assert.throws(()=>mod.mountIntoBoundary(document.createComment('a'),document.createComment('b')),/detached/);
    await Promise.resolve();dom.window.close();
}
console.log('Module runtime passed: '+cases.length+' native emitted modules with the real cell runtime and jsdom.');
''')
        runtime=run(['bun',str(harness)])
    finally:
        for path in temporary:path.unlink(missing_ok=True)
        shutil.rmtree(stage)
    static=sum(record['code'] is not None for record in outcomes.values())
    print(f'JavaScript {"flat" if FLAT else "static"} parity passed: {len(paths)} components + {len(templates)} targeted inputs; import/metadata bytes, {static} complete modules, dynamic rejection and {len(dataset)} entity cases checked ({time.monotonic()-started:.1f}s).')
    print(runtime.stdout.strip())


if __name__=='__main__':main()
