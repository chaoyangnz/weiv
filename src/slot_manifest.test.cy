import { parse } from .compiler.parser.template.parse;
import { normalize } from .compiler.parser.template.normalize;
import { build } from .compiler.sema.build_slot_manifest;
import { SlotManifestReport } from .compiler.sema.slot_manifest;

fn manifest_for(source: string): SlotManifestReport {
    const raw = parse(source.bytes()) catch (code) {
        panic("Expected raw template");
    };
    const normalized = normalize(&raw) catch (code) {
        panic("Expected normalized template");
    };
    return build(source.bytes(), &raw, &normalized);
}

test "empty and ordinary templates expose no slots" {
    const empty = manifest_for("");
    const ordinary = manifest_for("<p>Hello {{name}}</p>");
    assert(empty.manifest.entries.len() == 0);
    assert(ordinary.manifest.entries.len() == 0);
    assert(not ordinary.manifest.has_default());
    assert(not ordinary.manifest.has_name("header"));
    assert(ordinary.duplicates.len() == 0);
}

test "default and named slots preserve encounter order and source spans" {
    const result = manifest_for("<div><slot/><slot name=\"header\"/></div>");
    assert(result.manifest.entries.len() == 2);
    assert(result.manifest.has_default());
    assert(result.manifest.has_name("header"));
    assert(not result.manifest.has_name("Header"));
    if result.manifest.entries[0].name is name {
        assert(false);
    }
    if result.manifest.entries[1].name is name {
        assert(name == "header");
    } else {
        assert(false);
    }
    assert(result.manifest.entries[0].span.start == 5);
    assert(result.manifest.entries[0].span.end == 12);
    assert(result.manifest.entries[1].span.start == 12);
    assert(result.manifest.entries[1].span.end == 33);
    assert(result.duplicates.len() == 0);
}

test "explicit empty names remain distinct from default slots" {
    const result = manifest_for("<slot/><slot name=\"\"/><slot name=\"\"/><slot/>");
    assert(result.manifest.entries.len() == 4);
    assert(result.manifest.has_default());
    assert(result.manifest.has_name(""));
    assert(result.duplicates.len() == 2);
    if result.duplicates[0].name is name {
        assert(name == "");
    } else {
        assert(false);
    }
    if result.duplicates[1].name is name {
        assert(false);
    }
}

test "each later duplicate is reported once and retained in the manifest" {
    const result = manifest_for("<slot name=\"x\"/><slot name=\"x\"/><slot name=\"x\"/>");
    assert(result.manifest.entries.len() == 3);
    assert(result.duplicates.len() == 2);
    assert(result.duplicates[0].span.start == result.manifest.entries[1].span.start);
    assert(result.duplicates[1].span.start == result.manifest.entries[2].span.start);
    if result.duplicates[1].name is name {
        assert(name == "x");
    } else {
        assert(false);
    }
}

test "both conditional branches and loop bodies are discovered statically" {
    const result = manifest_for("<a #if=\"false\"><slot name=\"x\"/></a><b #else><slot name=\"x\"/></b><c #for=\"item in []\"><slot/></c>");
    assert(result.manifest.entries.len() == 3);
    assert(result.duplicates.len() == 1);
    assert(result.manifest.has_name("x"));
    assert(result.manifest.has_default());
}

test "outlet fallback descendants do not become public manifest entries" {
    const result = manifest_for("<slot name=\"outer\"><div><slot name=\"hidden\"/><slot name=\"outer\"/></div></slot><slot name=\"after\"/>");
    assert(result.manifest.entries.len() == 2);
    assert(result.manifest.has_name("outer"));
    assert(result.manifest.has_name("after"));
    assert(not result.manifest.has_name("hidden"));
    assert(result.duplicates.len() == 0);
}

test "normalization inside fallback does not expose nested declarations" {
    const result = manifest_for("<slot><a #if=\"x\"><slot name=\"hidden\"/></a><b #else><slot/></b></slot><slot/>");
    assert(result.manifest.entries.len() == 2);
    assert(result.duplicates.len() == 1);
    assert(not result.manifest.has_name("hidden"));
}

test "Unicode names stay valid after source and parser temporaries are gone" {
    const result = manifest_for("<slot name=\"标题🌱\"/>");
    const later = manifest_for("<slot name=\"another\"/>");
    assert(result.manifest.has_name("标题🌱"));
    assert(not result.manifest.has_name("another"));
    assert(later.manifest.has_name("another"));
}

test "projection directives do not declare component outlets" {
    const result = manifest_for("<Card slot:header/><p slot:body>body</p>");
    assert(result.manifest.entries.len() == 0);
    assert(result.duplicates.len() == 0);
}

test "build leaves raw and normalized arenas unchanged and may repeat" {
    const source = "<slot name=\"x\"/><slot name=\"x\"/>";
    const raw = parse(source.bytes()) catch (code) {
        panic("Expected parse");
    };
    const normalized = normalize(&raw) catch (code) {
        panic("Expected normalization");
    };
    const first = build(source.bytes(), &raw, &normalized);
    const second = build(source.bytes(), &raw, &normalized);
    assert(raw.nodes.len() == 2);
    assert(raw.attributes.len() == 2);
    assert(normalized.nodes.len() == 2);
    assert(first.manifest.entries.len() == second.manifest.entries.len());
    assert(first.duplicates.len() == second.duplicates.len());
}

test "deep ordinary nesting is traversed without recursive manifest calls" {
    var source = list<u8>();
    var i: usize = 0;
    while i < 1024 {
        for byte in "<a>".bytes() {
            source.push(byte);
        }
        i = i + 1;
    }
    for byte in "<slot/>".bytes() {
        source.push(byte);
    }
    i = 0;
    while i < 1024 {
        for byte in "</a>".bytes() {
            source.push(byte);
        }
        i = i + 1;
    }
    const raw = parse(source.view()) catch (code) {
        panic("Expected deep parse");
    };
    const normalized = normalize(&raw) catch (code) {
        panic("Expected deep normalization");
    };
    const result = build(source.view(), &raw, &normalized);
    assert(result.manifest.entries.len() == 1);
    assert(result.manifest.has_default());
    assert(result.manifest.entries[0].span.start == 3072);
}
