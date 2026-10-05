// idef0.rs -- Rust port of the idef0 tool (single file, zero dependencies).
// Build:  rustc -O idef0.rs -o idef0-rs
// Parity: byte-identical stdout/stderr with the Python `idef0` for
// lint | dump | links | text | html | svg | fmt on the same inputs.

use std::collections::{HashMap, HashSet};
use std::env;
use std::fs;

const USAGE: &str = "idef0 -- validator, formatter, and plate renderer for the pipe-path IDEF0 DSL.\n\nUsage:\n  idef0 lint  FILE...              validate; GNU-format diagnostics; exit 1 on errors\n  idef0 text  FILE...              render plates as character art, form-feed paginated\n  idef0 html  FILE...              render HTML drawing set (plates as SVG)\n  idef0 svg   NODE FILE...         render one plate (e.g. E22) as standalone SVG\n  idef0 dump  FILE...              print numbered model tree(s)\n  idef0 links FILE...              print project interface table\n  idef0 fmt [--number|--auto] [--write] FILE...\n                                   rewrite tag suffixes; --write edits in place\n                                   (fmt validates structure only, not links)\n\nGrammar summary (v1):\n  line := tag name [< path | > path]     tag := [taicom]( # | digit | LETTER | NUM. )\n  path := segment (| segment)*           ; comment lines start with ;\nSegment resolution order: child activity by name -> port by flow name\n(2+ matches = ambiguous error) -> port ref [icom]N -> node number.\nA '<' path ending at an activity with exactly one output takes that output.\n\nDiagnostics use GNU format  file:line: severity: message.\nExit status: 0 clean, 1 errors found, 2 usage failure.\n";

const INDENT: usize = 2;
const BOX_H: i64 = 5;
const CW: i64 = 9;
const CH: i64 = 18;
const PAD: i64 = 20;
const HALO: &str = " paint-order=\"stroke\" stroke=\"#fdfcf8\" stroke-width=\"3\"";

#[derive(Default, Clone)]
struct Node {
    doc: Vec<String>,
    trail: Option<String>,
    tag: char,
    suffix: String,
    variant: Option<String>,
    name: String,
    link_dir: Option<char>,
    link_path: Vec<String>,
    fname: String,
    line: u32,
    indent: usize,
    parent: Option<usize>,
    children: Vec<usize>,
    ports: Vec<usize>,
    number: Option<u32>,
    letter: char,
    node_id: String,
    asserted: Option<String>,
    link_target: Option<usize>,
    model: Option<usize>,
}

impl Node {
    fn is_activity(&self) -> bool {
        self.tag == 't' || self.tag == 'a'
    }
}

struct Rec {
    raw: String,
    node: Option<usize>,
}

type Diag = (String, u32, &'static str, String);

struct Arena {
    n: Vec<Node>,
}

impl Arena {
    fn descendants(&self, id: usize) -> Vec<usize> {
        let mut out = Vec::new();
        for &k in &self.n[id].children {
            out.push(k);
            out.extend(self.descendants(k));
        }
        out
    }
    fn all_ports(&self, id: usize) -> Vec<usize> {
        let mut out: Vec<usize> = self.n[id].ports.clone();
        for &k in &self.n[id].children {
            out.extend(self.all_ports(k));
        }
        out
    }
}

fn err(diags: &mut Vec<Diag>, fname: &str, line: u32, sev: &'static str, msg: String) {
    diags.push((fname.to_string(), line, sev, msg));
}

fn py_repr(s: &str) -> String {
    let (q, esc_q) = if s.contains('\'') && !s.contains('"') {
        ('"', '"')
    } else {
        ('\'', '\'')
    };
    let mut o = String::new();
    o.push(q);
    for c in s.chars() {
        match c {
            '\\' => o.push_str("\\\\"),
            '\n' => o.push_str("\\n"),
            '\r' => o.push_str("\\r"),
            '\t' => o.push_str("\\t"),
            c if c == esc_q => {
                o.push('\\');
                o.push(c);
            }
            c if (c as u32) < 0x20 => o.push_str(&format!("\\x{:02x}", c as u32)),
            c => o.push(c),
        }
    }
    o.push(q);
    o
}

fn esc(s: &str) -> String {
    let mut o = String::new();
    for c in s.chars() {
        match c {
            '&' => o.push_str("&amp;"),
            '<' => o.push_str("&lt;"),
            '>' => o.push_str("&gt;"),
            '"' => o.push_str("&quot;"),
            '\'' => o.push_str("&#x27;"),
            c => o.push(c),
        }
    }
    o
}

// ------------------------------------------------------------------ parsing
fn fence_open_len(raw: &str) -> Option<usize> {
    let ticks = raw.chars().take_while(|&c| c == '`').count();
    if ticks < 3 {
        return None;
    }
    let rest = &raw[ticks..];
    let rest = rest.trim();
    if rest == "idef0" {
        Some(ticks)
    } else {
        None
    }
}

fn fence_close(raw: &str) -> bool {
    let ticks = raw.chars().take_while(|&c| c == '`').count();
    ticks >= 3 && raw[ticks..].trim().is_empty()
}

struct TagMatch {
    indent: String,
    tag: char,
    variant: Option<String>,
    suffix: String,
    rest: Option<String>,
}

fn tag_match(raw: &str) -> Option<TagMatch> {
    let chars: Vec<char> = raw.chars().collect();
    let mut i = 0;
    while i < chars.len() && (chars[i] == ' ' || chars[i] == '\t') {
        i += 1;
    }
    let indent: String = chars[..i].iter().collect();
    if i >= chars.len() {
        return None;
    }
    let tag = chars[i];
    if !"taicom".contains(tag) {
        return None;
    }
    i += 1;
    let mut variant: Option<String> = None;
    if i < chars.len() && chars[i] == '/' {
        let mut v = String::from("/");
        i += 1;
        if i < chars.len() && chars[i].is_ascii_lowercase() {
            v.push(chars[i]);
            i += 1;
        }
        variant = Some(v);
    }
    // suffix := '#' | [A-Za-z]?\d+\. | [A-Za-z]?\d*
    let s = &chars[i..];
    let take_rest = |j: usize| -> Option<Option<String>> {
        // after suffix ends at offset j (into s): (?:\s+(rest))?$
        if j == s.len() {
            return Some(None);
        }
        if !(s[j] == ' ' || s[j] == '\t') {
            return None;
        }
        let mut k = j;
        while k < s.len() && (s[k] == ' ' || s[k] == '\t') {
            k += 1;
        }
        let rest: String = s[k..].iter().collect();
        Some(Some(rest))
    };
    // alt 1: '#'
    if !s.is_empty() && s[0] == '#' {
        if let Some(rest) = take_rest(1) {
            return Some(TagMatch { indent, tag, variant, suffix: "#".into(), rest });
        }
        return None;
    }
    let mut j = 0;
    let mut letter = String::new();
    if j < s.len() && s[j].is_ascii_alphabetic() {
        letter.push(s[j]);
        j += 1;
    }
    let dstart = j;
    while j < s.len() && s[j].is_ascii_digit() {
        j += 1;
    }
    let digits: String = s[dstart..j].iter().collect();
    // alt 2: letter?digits+'.'
    if !digits.is_empty() && j < s.len() && s[j] == '.' {
        if let Some(rest) = take_rest(j + 1) {
            return Some(TagMatch {
                indent,
                tag,
                variant,
                suffix: format!("{}{}.", letter, digits),
                rest,
            });
        }
    }
    // alt 3: letter?digits*
    if let Some(rest) = take_rest(j) {
        return Some(TagMatch {
            indent,
            tag,
            variant,
            suffix: format!("{}{}", letter, digits),
            rest,
        });
    }
    // backtrack: letter absorbed but maybe letter belongs to rest? The Python
    // regex would also try suffix="" with rest starting at the letter -- but
    // rest requires preceding whitespace, and the letter is glued to the tag,
    // so no shorter match can succeed either. One more case: digits matched
    // greedily can not shrink to satisfy \s, since digits are not whitespace.
    None
}

fn trailing_comment(raw: &str) -> Option<(usize, String)> {
    // first whitespace followed by '#'
    let b: Vec<char> = raw.chars().collect();
    for i in 0..b.len().saturating_sub(1) {
        if (b[i] == ' ' || b[i] == '\t') && b[i + 1] == '#' {
            let trail: String = b[i + 1..].iter().collect();
            let code: String = b[..i].iter().collect();
            return Some((code.len(), trail)).map(|_| (0, String::new())).and(Some((i, trail_of(&b, i))));
        }
    }
    None
}

fn trail_of(b: &[char], i: usize) -> String {
    b[i + 1..].iter().collect()
}

fn parse_file(
    a: &mut Arena,
    fname: &str,
    text: &str,
    diags: &mut Vec<Diag>,
    records: &mut Vec<Rec>,
) -> Vec<usize> {
    let mut roots: Vec<usize> = Vec::new();
    let mut stack: Vec<(usize, usize)> = Vec::new(); // (level, node)
    let mut last_node: Option<usize> = None;
    let lf = fname.to_lowercase();
    let is_md = lf.ends_with(".md") || lf.ends_with(".markdown");
    let mut in_fence = !is_md;
    let mut fence_len = 0usize;
    let mut fence_line = 0u32;
    for (ln0, raw) in text.lines().enumerate() {
        let lineno = (ln0 + 1) as u32;
        if is_md {
            if !in_fence {
                if let Some(fl) = fence_open_len(raw) {
                    in_fence = true;
                    fence_len = fl;
                    fence_line = lineno;
                }
                records.push(Rec { raw: raw.into(), node: None });
                continue;
            }
            if fence_close(raw) && raw.trim().chars().count() >= fence_len {
                in_fence = false;
                records.push(Rec { raw: raw.into(), node: None });
                continue;
            }
        }
        let stripped = raw.trim();
        if stripped.starts_with(";;") || stripped.starts_with("##") {
            let txt = stripped[2..].trim().to_string();
            match last_node {
                None => err(
                    diags,
                    fname,
                    lineno,
                    "warning",
                    format!(
                        "'{}' doc comment has no element line to attach to",
                        &stripped[..2]
                    ),
                ),
                Some(idx) => {
                    let t = if txt.is_empty() { "\\n".to_string() } else { txt };
                    a.n[idx].doc.push(t);
                }
            }
            records.push(Rec { raw: raw.into(), node: None });
            continue;
        }
        if stripped.is_empty() || stripped.starts_with(';') || stripped.starts_with('#') {
            records.push(Rec { raw: raw.into(), node: None });
            continue;
        }
        let (raw_code, trail): (String, Option<String>) = match trailing_comment(raw) {
            Some((i, t)) => (raw.chars().take(i).collect(), Some(t)),
            None => (raw.to_string(), None),
        };
        let m = match tag_match(&raw_code) {
            Some(m) => m,
            None => {
                err(
                    diags,
                    fname,
                    lineno,
                    "error",
                    format!("cannot parse line: {}", py_repr(stripped)),
                );
                records.push(Rec { raw: raw.into(), node: None });
                continue;
            }
        };
        let mut indent = m.indent.clone();
        if indent.contains('\t') {
            err(
                diags,
                fname,
                lineno,
                "error",
                "tabs in indentation; use 2 spaces per level".into(),
            );
            indent = indent.replace('\t', "  ");
        }
        if indent.chars().count() % INDENT != 0 {
            err(
                diags,
                fname,
                lineno,
                "error",
                format!(
                    "indentation of {} is not a multiple of {}",
                    indent.chars().count(),
                    INDENT
                ),
            );
        }
        let level = indent.chars().count() / INDENT;
        let tag = m.tag;
        let mut variant = m.variant.clone();
        if let Some(v) = variant.clone() {
            if tag == 'm' && v.chars().count() > 1 {
                err(diags, fname, lineno, "error",
                    "mechanism kind takes a bare '/' (module means); letters after '/' are reserved".into());
                variant = Some("/".to_string());
            } else if tag != 'o' && tag != 'm' {
                err(diags, fname, lineno, "error",
                    format!("'/' marks exclusive outputs (o/) or module mechanisms (m/); not valid on '{}'", tag));
                variant = None;
            }
        }
        let suffix = if m.suffix.is_empty() { "#".to_string() } else { m.suffix.clone() };
        let rest = m.rest.clone().unwrap_or_default().trim().to_string();

        let mut link_dir: Option<char> = None;
        let mut link_path: Vec<String> = Vec::new();
        let mut name = rest.clone();
        if let Some(lp) = rest.find(|c| c == '<' || c == '>') {
            link_dir = rest[lp..].chars().next();
            name = rest[..lp].trim().to_string();
            let path_txt = rest[lp + 1..].trim().to_string();
            link_path = path_txt.split('|').map(|s| s.trim().to_string()).collect();
            if link_path.iter().any(|s| s.is_empty()) {
                err(diags, fname, lineno, "error", "empty segment in link path".into());
            }
        }
        if name.contains('|') {
            err(
                diags,
                fname,
                lineno,
                "error",
                "'|' not allowed in a name (link paths follow < or >)".into(),
            );
            name = name.replace('|', " ");
        }
        if name.is_empty() {
            err(diags, fname, lineno, "error", format!("'{}' line has no name", tag));
        }

        let idx = a.n.len();
        a.n.push(Node {
            tag,
            suffix,
            name,
            link_dir,
            link_path,
            fname: fname.to_string(),
            line: lineno,
            indent: indent.chars().count(),
            ..Default::default()
        });
        a.n[idx].variant = variant;
        a.n[idx].trail = trail.clone();
        if let Some(t) = &trail {
            if t.starts_with("##") {
                let dt = t[2..].trim().to_string();
                let dt = if dt.is_empty() { "\\n".to_string() } else { dt };
                a.n[idx].doc.push(dt);
            }
        }
        records.push(Rec { raw: raw.into(), node: Some(idx) });
        last_node = Some(idx);

        if tag == 't' {
            if level != 0 {
                err(
                    diags,
                    fname,
                    lineno,
                    "error",
                    "model root 't' must be at indentation 0".into(),
                );
            }
            roots.push(idx);
            stack = vec![(0, idx)];
            continue;
        }
        while let Some(&(pl, _)) = stack.last() {
            if pl >= level {
                stack.pop();
            } else {
                break;
            }
        }
        if stack.is_empty() {
            err(
                diags,
                fname,
                lineno,
                "error",
                format!("'{}' line has no parent model/activity", tag),
            );
            continue;
        }
        let (plevel, parent) = *stack.last().unwrap();
        if plevel != level.wrapping_sub(1) {
            err(
                diags,
                fname,
                lineno,
                "error",
                format!("indentation jumps from level {} to {}", plevel, level),
            );
        }
        a.n[idx].parent = Some(parent);
        if tag == 'a' {
            if !a.n[parent].is_activity() {
                err(diags, fname, lineno, "error", "activity nested under a port".into());
            } else {
                a.n[parent].children.push(idx);
                stack.push((level, idx));
            }
        } else if !a.n[parent].is_activity() {
            err(diags, fname, lineno, "error", "port nested under a port".into());
        } else {
            a.n[parent].ports.push(idx);
        }
    }
    if is_md && in_fence {
        err(
            diags,
            fname,
            fence_line,
            "warning",
            "unclosed ```idef0 fence at end of file".into(),
        );
    }
    roots
}

// --------------------------------------------------------------- numbering
struct OMap {
    order: Vec<String>,
    map: HashMap<String, Vec<usize>>,
}
impl OMap {
    fn new() -> Self {
        OMap { order: Vec::new(), map: HashMap::new() }
    }
    fn push(&mut self, k: &str, v: usize) {
        if !self.map.contains_key(k) {
            self.order.push(k.to_string());
        }
        self.map.entry(k.to_string()).or_default().push(v);
    }
    fn get(&self, k: &str) -> Option<&Vec<usize>> {
        self.map.get(k)
    }
}

struct Project {
    a: Arena,
    models: Vec<usize>,
    letters_order: Vec<char>,
    letters: HashMap<char, usize>,
    producers: HashMap<usize, OMap>,
    consumers: HashMap<usize, OMap>,
    rows: Vec<(usize, usize, String)>,
    doc: Vec<(String, Vec<Rec>)>,
}

fn assign_numbers(p: &mut Project, diags: &mut Vec<Diag>) {
    for mi in 0..p.models.len() {
        let t = p.models[mi];
        let s = p.a.n[t].suffix.clone();
        let letter: char;
        if s == "#" || s.is_empty() {
            let alpha: Vec<char> = p.a.n[t].name.chars().filter(|c| c.is_alphabetic()).collect();
            letter = alpha.first().map(|c| c.to_ascii_uppercase()).unwrap_or('X');
        } else if s.chars().count() == 1 && s.chars().next().unwrap().is_ascii_alphabetic() {
            letter = s.chars().next().unwrap().to_ascii_uppercase();
        } else {
            let (f, l) = (p.a.n[t].fname.clone(), p.a.n[t].line);
            err(diags, &f, l, "error",
                format!("bad model suffix {}: use a single letter or #", py_repr(&s)));
            letter = 'X';
        }
        if let Some(&prev) = p.letters.get(&letter) {
            let (f, l) = (p.a.n[t].fname.clone(), p.a.n[t].line);
            err(diags, &f, l, "error",
                format!("duplicate model letter '{}' (also {})", letter, py_repr(&p.a.n[prev].name)));
        } else {
            p.letters_order.push(letter);
        }
        p.letters.insert(letter, t);
        p.a.n[t].letter = letter;
        p.a.n[t].node_id = letter.to_string();
        p.a.n[t].model = Some(t);
        number_children(&mut p.a, t, diags);
        number_ports(&mut p.a, t, diags);
        for pi in p.a.n[t].ports.clone() {
            p.a.n[pi].model = Some(t);
        }
        for ai in p.a.descendants(t) {
            p.a.n[ai].model = Some(t);
            number_ports(&mut p.a, ai, diags);
            for pi in p.a.n[ai].ports.clone() {
                p.a.n[pi].model = Some(t);
            }
        }
    }
}

fn number_children(a: &mut Arena, act: usize, diags: &mut Vec<Diag>) {
    let kids = a.n[act].children.clone();
    if kids.len() > 9 {
        let (f, l) = (a.n[act].fname.clone(), a.n[act].line);
        err(diags, &f, l, "error", "more than 9 activities on one plate".into());
    }
    let mut pinned: HashMap<u32, usize> = HashMap::new();
    for &k in &kids {
        let s = a.n[k].suffix.clone();
        a.n[k].asserted = None;
        if s.ends_with('.') {
            a.n[k].asserted = Some(s[..s.len() - 1].to_string());
            continue;
        }
        if !s.is_empty() && s != "#" && s.chars().all(|c| c.is_ascii_digit()) {
            if s.chars().count() != 1 || s == "0" {
                let (f, l) = (a.n[k].fname.clone(), a.n[k].line);
                err(diags, &f, l, "error",
                    format!("pinned number {} must be a single digit 1-9", py_repr(&s)));
                continue;
            }
            let d: u32 = s.parse().unwrap();
            if let Some(&prev) = pinned.get(&d) {
                let (f, l) = (a.n[k].fname.clone(), a.n[k].line);
                err(diags, &f, l, "error",
                    format!("duplicate pinned digit {} on plate {} (also line {})",
                            d, a.n[act].node_id, a.n[prev].line));
            } else {
                pinned.insert(d, k);
                a.n[k].number = Some(d);
            }
        } else if !s.is_empty() && s != "#" && !s.ends_with('.') {
            let (f, l) = (a.n[k].fname.clone(), a.n[k].line);
            err(diags, &f, l, "error", format!("bad activity suffix {}", py_repr(&s)));
        }
    }
    let mut nxt: u32 = 1;
    for &k in &kids {
        if a.n[k].number.is_none() {
            while pinned.contains_key(&nxt) {
                nxt += 1;
            }
            a.n[k].number = Some(nxt);
            pinned.insert(nxt, k);
            nxt += 1;
        }
    }
    let base = if a.n[act].tag == 'a' {
        a.n[act].node_id.clone()
    } else {
        a.n[act].letter.to_string()
    };
    for &k in &kids {
        a.n[k].node_id = format!("{}{}", base, a.n[k].number.unwrap());
        if let Some(asrt) = a.n[k].asserted.clone() {
            if asrt != a.n[k].node_id {
                let (f, l) = (a.n[k].fname.clone(), a.n[k].line);
                let nid = a.n[k].node_id.clone();
                err(diags, &f, l, "error",
                    format!("asserted number {} but position derives {}", asrt, nid));
            }
        }
        number_children(a, k, diags);
    }
}

fn number_ports(a: &mut Arena, act: usize, diags: &mut Vec<Diag>) {
    let mut vg_order: Vec<String> = Vec::new();
    let mut vgroups: HashMap<String, Vec<usize>> = HashMap::new();
    for &pi in &a.n[act].ports {
        if a.n[pi].tag != 'o' {
            continue;
        }
        if let Some(v) = a.n[pi].variant.clone() {
            if !vgroups.contains_key(&v) {
                vg_order.push(v.clone());
            }
            vgroups.entry(v).or_default().push(pi);
        }
    }
    for key in &vg_order {
        let ps = &vgroups[key];
        if ps.len() < 2 {
            let (f, l) = (a.n[ps[0]].fname.clone(), a.n[ps[0]].line);
            let an = a.n[act].name.clone();
            err(diags, &f, l, "warning",
                format!("variant group 'o{}' on '{}' has a single member; an exclusive set needs at least 2",
                        key, an));
        }
    }
    let mut counts: HashMap<char, u32> = HashMap::new();
    for pi in a.n[act].ports.clone() {
        let s = a.n[pi].suffix.clone();
        let mut n: Option<u32> = None;
        if s.ends_with('.') {
            let (f, l) = (a.n[pi].fname.clone(), a.n[pi].line);
            err(diags, &f, l, "error",
                "asserted numbers are for activities; ports take # or a digit".into());
        } else if !s.is_empty() && s.chars().all(|c| c.is_ascii_digit()) {
            if s.chars().count() != 1 || s == "0" {
                let (f, l) = (a.n[pi].fname.clone(), a.n[pi].line);
                err(diags, &f, l, "error",
                    format!("pinned port number {} must be a single digit 1-9", py_repr(&s)));
            } else {
                n = Some(s.parse().unwrap());
            }
        } else if !s.is_empty() && s != "#" {
            let (f, l) = (a.n[pi].fname.clone(), a.n[pi].line);
            err(diags, &f, l, "error", format!("bad port suffix {}", py_repr(&s)));
        }
        let tag = a.n[pi].tag;
        let nv = match n {
            Some(v) => v,
            None => counts.get(&tag).copied().unwrap_or(0) + 1,
        };
        let cur = counts.get(&tag).copied().unwrap_or(0);
        counts.insert(tag, cur.max(nv));
        a.n[pi].number = Some(nv);
        a.n[pi].node_id = format!("{}.{}{}", a.n[act].node_id, tag, nv);
        if a.n[pi].link_dir == Some('<') && tag == 'o' {
            let (f, l) = (a.n[pi].fname.clone(), a.n[pi].line);
            err(diags, &f, l, "error", "outputs declare goes-to with '>', not '<'".into());
        }
        if a.n[pi].link_dir == Some('>') && (tag == 'i' || tag == 'c' || tag == 'm') {
            let (f, l) = (a.n[pi].fname.clone(), a.n[pi].line);
            err(diags, &f, l, "error",
                format!("'{}' ports declare comes-from with '<', not '>'", tag));
        }
    }
}

// --------------------------------------------------------------- difflib
fn find_longest(a: &[char], b2j: &HashMap<char, Vec<usize>>, alo: usize, ahi: usize,
                blo: usize, bhi: usize) -> (usize, usize, usize) {
    let (mut besti, mut bestj, mut bestk) = (alo, blo, 0usize);
    let mut j2len: HashMap<usize, usize> = HashMap::new();
    for i in alo..ahi {
        let mut newj: HashMap<usize, usize> = HashMap::new();
        if let Some(js) = b2j.get(&a[i]) {
            for &j in js {
                if j < blo {
                    continue;
                }
                if j >= bhi {
                    break;
                }
                let k = if j == 0 { 1 } else { j2len.get(&(j - 1)).copied().unwrap_or(0) + 1 };
                newj.insert(j, k);
                if k > bestk {
                    besti = i + 1 - k;
                    bestj = j + 1 - k;
                    bestk = k;
                }
            }
        }
        j2len = newj;
    }
    (besti, bestj, bestk)
}

fn seq_ratio(xa: &str, xb: &str) -> f64 {
    let a: Vec<char> = xa.chars().collect();
    let b: Vec<char> = xb.chars().collect();
    let mut b2j: HashMap<char, Vec<usize>> = HashMap::new();
    for (j, &c) in b.iter().enumerate() {
        b2j.entry(c).or_default().push(j);
    }
    let mut matches = 0usize;
    let mut queue = vec![(0usize, a.len(), 0usize, b.len())];
    while let Some((alo, ahi, blo, bhi)) = queue.pop() {
        let (i, j, k) = find_longest(&a, &b2j, alo, ahi, blo, bhi);
        if k > 0 {
            matches += k;
            queue.push((alo, i, blo, j));
            queue.push((i + k, ahi, j + k, bhi));
        }
    }
    let t = a.len() + b.len();
    if t == 0 {
        return 1.0;
    }
    2.0 * matches as f64 / t as f64
}

fn close_one<I: IntoIterator<Item = String>>(word: &str, poss: I, cutoff: f64) -> Option<String> {
    let mut best: Option<(f64, String)> = None;
    for x in poss {
        let r = seq_ratio(&x, word);
        if r >= cutoff {
            let better = match &best {
                None => true,
                Some((br, bx)) => r > *br || (r == *br && x > *bx),
            };
            if better {
                best = Some((r, x));
            }
        }
    }
    best.map(|(_, x)| x)
}

// --------------------------------------------------------------- wiring
fn wire_model(p: &mut Project, t: usize, diags: &mut Vec<Diag>) {
    let mut producers = OMap::new();
    let mut consumers = OMap::new();
    for pi in p.a.all_ports(t) {
        let name = p.a.n[pi].name.clone();
        if p.a.n[pi].tag == 'o' {
            producers.push(&name, pi);
        } else {
            consumers.push(&name, pi);
        }
    }
    for name in consumers.order.clone() {
        if producers.map.contains_key(&name) {
            continue;
        }
        let cands = close_one(&name, producers.order.iter().cloned(), 0.86);
        for &pi in consumers.get(&name).unwrap() {
            if p.a.n[pi].link_dir.is_some() {
                continue;
            }
            if let Some(c) = &cands {
                let (f, l) = (p.a.n[pi].fname.clone(), p.a.n[pi].line);
                err(diags, &f, l, "warning",
                    format!("'{}' has no producer; did you mean '{}'?", name, c));
            }
        }
    }
    for name in producers.order.clone() {
        if consumers.map.contains_key(&name) {
            continue;
        }
        let cands = close_one(&name, consumers.order.iter().cloned(), 0.86);
        for &pi in producers.get(&name).unwrap() {
            if p.a.n[pi].link_dir.is_some() {
                continue;
            }
            if let Some(c) = &cands {
                let (f, l) = (p.a.n[pi].fname.clone(), p.a.n[pi].line);
                err(diags, &f, l, "warning",
                    format!("'{}' has no consumer; did you mean '{}'?", name, c));
            }
        }
    }
    p.producers.insert(t, producers);
    p.consumers.insert(t, consumers);
}

// --------------------------------------------------------------- links
enum WalkErr {
    Ambig(usize, String),
}

fn walk(a: &Arena, scope: usize, segs: &[String], want: char) -> Result<Option<usize>, WalkErr> {
    let mut cur = scope;
    for (i, seg) in segs.iter().enumerate() {
        let last = i == segs.len() - 1;
        let kids: Vec<usize> = a.n[cur].children.iter().copied()
            .filter(|&k| a.n[k].name == *seg).collect();
        if kids.len() == 1 {
            cur = kids[0];
            continue;
        }
        let pmatch: Vec<usize> = a.n[cur].ports.iter().copied()
            .filter(|&pp| a.n[pp].name == *seg).collect();
        if pmatch.len() >= 2 {
            return Err(WalkErr::Ambig(cur, seg.clone()));
        }
        if pmatch.len() == 1 {
            return Ok(if last { Some(pmatch[0]) } else { None });
        }
        let sc: Vec<char> = seg.chars().collect();
        if sc.len() == 2 && "icom".contains(sc[0]) && ('1'..='9').contains(&sc[1]) {
            let num = sc[1].to_digit(10).unwrap();
            let pr: Vec<usize> = a.n[cur].ports.iter().copied()
                .filter(|&pp| a.n[pp].tag == sc[0] && a.n[pp].number == Some(num)).collect();
            if !pr.is_empty() {
                return Ok(if last { Some(pr[0]) } else { None });
            }
        }
        let nn: Vec<usize> = a.n[cur].children.iter().copied()
            .filter(|&k| a.n[k].node_id == *seg).collect();
        if nn.len() == 1 {
            cur = nn[0];
            continue;
        }
        return Ok(None);
    }
    if want == '<' {
        let outs: Vec<usize> = a.n[cur].ports.iter().copied()
            .filter(|&pp| a.n[pp].tag == 'o').collect();
        if outs.len() == 1 {
            return Ok(Some(outs[0]));
        }
    }
    Ok(None)
}

fn suggest(p: &Project, segs: &[String], scope_model: Option<usize>) -> String {
    let mut names: HashSet<String> = HashSet::new();
    for c in &p.letters_order {
        names.insert(c.to_string());
    }
    for (&_c, &t) in &p.letters {
        names.insert(p.a.n[t].name.clone());
    }
    if let Some(sm) = scope_model {
        for ai in p.a.descendants(sm) {
            names.insert(p.a.n[ai].name.clone());
            names.insert(p.a.n[ai].node_id.clone());
        }
    }
    for seg in segs {
        if names.contains(seg) {
            continue;
        }
        if let Some(close) = close_one(seg, names.iter().cloned(), 0.75) {
            return format!(" (closest: '{}')", close);
        }
    }
    String::new()
}

fn resolve_links(p: &mut Project, diags: &mut Vec<Diag>) {
    let mut by_name: HashMap<String, usize> = HashMap::new();
    for &t in &p.models {
        by_name.insert(p.a.n[t].name.clone(), t);
    }
    let mut cross: Vec<(usize, usize, usize)> = Vec::new();
    for &t in &p.models.clone() {
        for pi in p.a.all_ports(t) {
            let dir = match p.a.n[pi].link_dir {
                Some(d) => d,
                None => continue,
            };
            let segs = p.a.n[pi].link_path.clone();
            let mut target: Option<usize> = None;
            let mut addressed: Option<usize> = Some(t);
            let mut ambig: Option<(usize, String)> = None;
            let mut scope = p.a.n[pi].parent;
            while let Some(sc) = scope {
                match walk(&p.a, sc, &segs, dir) {
                    Ok(Some(x)) => {
                        target = Some(x);
                        break;
                    }
                    Ok(None) => {}
                    Err(WalkErr::Ambig(act, flow)) => {
                        ambig = Some((act, flow));
                        break;
                    }
                }
                scope = p.a.n[sc].parent;
            }
            if ambig.is_none() && target.is_none() && !segs.is_empty() {
                let first: Vec<char> = segs[0].chars().collect();
                let mt = if first.len() == 1 {
                    p.letters.get(&first[0]).copied()
                } else {
                    None
                }
                .or_else(|| by_name.get(&segs[0]).copied());
                if let Some(mt) = mt {
                    if segs.len() > 1 {
                        addressed = Some(mt);
                        match walk(&p.a, mt, &segs[1..], dir) {
                            Ok(x) => target = x,
                            Err(WalkErr::Ambig(act, flow)) => ambig = Some((act, flow)),
                        }
                    }
                }
            }
            if let Some((act, flow)) = ambig {
                let (f, l) = (p.a.n[pi].fname.clone(), p.a.n[pi].line);
                let an = p.a.n[act].name.clone();
                err(diags, &f, l, "error",
                    format!("'{}' has no unique port for flow '{}'; add the port or use o1/i1 form",
                            an, flow));
                continue;
            }
            let target = match target {
                Some(x) => x,
                None => {
                    let hint = suggest(p, &segs, addressed);
                    let (f, l) = (p.a.n[pi].fname.clone(), p.a.n[pi].line);
                    err(diags, &f, l, "error",
                        format!("broken link: cannot resolve '{}'{}", segs.join("|"), hint));
                    continue;
                }
            };
            p.a.n[pi].link_target = Some(target);
            let (src, dst) = if dir == '<' { (target, pi) } else { (pi, target) };
            if p.a.n[src].tag != 'o' && !(p.a.n[src].tag == 'm' && p.a.n[dst].tag == 'm') {
                let (f, l) = (p.a.n[pi].fname.clone(), p.a.n[pi].line);
                let (sid, stag) = (p.a.n[src].node_id.clone(), p.a.n[src].tag);
                err(diags, &f, l, "warning",
                    format!("link source '{}' is '{}' -- flows must originate at an output",
                            sid, stag));
            }
            if p.a.n[dst].tag == 'o' {
                let (f, l) = (p.a.n[pi].fname.clone(), p.a.n[pi].line);
                let did = p.a.n[dst].node_id.clone();
                err(diags, &f, l, "warning",
                    format!("link destination '{}' is an output", did));
            }
            if p.a.n[src].model != p.a.n[dst].model {
                cross.push((src, dst, pi));
            }
        }
    }
    for &(src, dst, via) in &cross {
        let other = if via == src { dst } else { src };
        if p.a.n[other].link_dir.is_none() {
            let (f, l) = (p.a.n[via].fname.clone(), p.a.n[via].line);
            let (oid, oname) = (p.a.n[other].node_id.clone(), p.a.n[other].name.clone());
            let d = if p.a.n[other].tag == 'o' { '>' } else { '<' };
            err(diags, &f, l, "warning",
                format!("one-sided cross-model link: {} '{}' does not declare the reciprocal {} link",
                        oid, oname, d));
        }
    }
    let mut rows: Vec<(usize, usize, String)> = Vec::new();
    let mut seen: HashSet<(String, String, String)> = HashSet::new();
    for &(src, dst, _) in &cross {
        let names: Vec<String> = if p.a.n[src].name == p.a.n[dst].name {
            vec![p.a.n[src].name.clone()]
        } else {
            vec![p.a.n[src].name.clone(), p.a.n[dst].name.clone()]
        };
        for name in names {
            let key = (p.a.n[src].node_id.clone(), p.a.n[dst].node_id.clone(), name.clone());
            if seen.contains(&key) {
                continue;
            }
            seen.insert(key);
            rows.push((src, dst, name));
        }
    }
    rows.sort_by(|x, y| {
        let mx = p.a.n[x.0].model.unwrap();
        let my = p.a.n[y.0].model.unwrap();
        (p.a.n[mx].letter, &p.a.n[x.0].node_id, &p.a.n[x.1].node_id, &x.2)
            .cmp(&(p.a.n[my].letter, &p.a.n[y.0].node_id, &p.a.n[y.1].node_id, &y.2))
    });
    p.rows = rows;
}

// --------------------------------------------------------------- project
fn load_project(files: &[String], diags: &mut Vec<Diag>, links_too: bool) -> Project {
    let mut p = Project {
        a: Arena { n: Vec::new() },
        models: Vec::new(),
        letters_order: Vec::new(),
        letters: HashMap::new(),
        producers: HashMap::new(),
        consumers: HashMap::new(),
        rows: Vec::new(),
        doc: Vec::new(),
    };
    for f in files {
        let text = match fs::read_to_string(f) {
            Ok(t) => t,
            Err(e) => {
                let emsg = if e.kind() == std::io::ErrorKind::NotFound {
                    format!("[Errno 2] No such file or directory: '{}'", f)
                } else {
                    format!("{}", e)
                };
                eprintln!("idef0: cannot read {}: {}", f, emsg);
                std::process::exit(2);
            }
        };
        let mut recs: Vec<Rec> = Vec::new();
        let roots = parse_file(&mut p.a, f, &text, diags, &mut recs);
        p.doc.push((f.clone(), recs));
        p.models.extend(roots);
    }
    assign_numbers(&mut p, diags);
    if links_too {
        for t in p.models.clone() {
            wire_model(&mut p, t, diags);
        }
        resolve_links(&mut p, diags);
    }
    p
}

fn emit_diags(diags: &Vec<Diag>, to_stderr: bool) -> (usize, usize) {
    let errs = diags.iter().filter(|d| d.2 == "error").count();
    let warns = diags.iter().filter(|d| d.2 == "warning").count();
    let mut sorted: Vec<&Diag> = diags.iter().collect();
    sorted.sort_by(|x, y| (&x.0, x.1).cmp(&(&y.0, y.1)));
    for (f, ln, sev, msg) in sorted {
        let line = format!("{}:{}: {}: {}", f, ln, sev, msg);
        if to_stderr {
            eprintln!("{}", line);
        } else {
            println!("{}", line);
        }
    }
    (errs, warns)
}

fn summary(p: &Project, files: &[String], diags: &Vec<Diag>) -> usize {
    let errs = diags.iter().filter(|d| d.2 == "error").count();
    let warns = diags.iter().filter(|d| d.2 == "warning").count();
    let acts: usize = p.models.iter().map(|&t| p.a.descendants(t).len()).sum();
    println!(
        "{} file(s): {} error(s), {} warning(s), {} model(s), {} activities, {} link(s)",
        files.len(), errs, warns, p.models.len(), acts, p.rows.len()
    );
    errs
}

fn cmd_lint(files: &[String]) -> i32 {
    let mut diags = Vec::new();
    let p = load_project(files, &mut diags, true);
    emit_diags(&diags, false);
    if summary(&p, files, &diags) > 0 { 1 } else { 0 }
}

fn cmd_dump(files: &[String]) -> i32 {
    let mut diags = Vec::new();
    let p = load_project(files, &mut diags, true);
    let (errs, _) = emit_diags(&diags, false);
    for &t in &p.models {
        println!("{}  {}    [{}]", p.a.n[t].node_id, p.a.n[t].name, p.a.n[t].fname);
        fn rec(p: &Project, a: usize, depth: usize) {
            for &pi in &p.a.n[a].ports {
                let lk = match p.a.n[pi].link_dir {
                    Some(d) => format!("  {} {}", d, p.a.n[pi].link_path.join("|")),
                    None => String::new(),
                };
                println!("{}{:<12} {}{} {}{}",
                         "  ".repeat(depth), p.a.n[pi].node_id,
                         p.a.n[pi].tag.to_ascii_uppercase(),
                         p.a.n[pi].variant.clone().unwrap_or_default(),
                         p.a.n[pi].name, lk);
            }
            for &k in &p.a.n[a].children {
                let pure = if effect_clean(&p.a, k) { "  [pure]" } else { "" };
                println!("{}{:<12} {}{}", "  ".repeat(depth), p.a.n[k].node_id, p.a.n[k].name, pure);
                rec(p, k, depth + 1);
            }
        }
        rec(&p, t, 1);
        println!();
    }
    if errs > 0 { 1 } else { 0 }
}

fn cmd_links(files: &[String]) -> i32 {
    let mut diags = Vec::new();
    let p = load_project(files, &mut diags, true);
    let (errs, _) = emit_diags(&diags, false);
    println!("{:<14} {:<14} FLOW", "SOURCE", "DEST");
    for (s, d, name) in &p.rows {
        println!("{:<14} {:<14} {}", p.a.n[*s].node_id, p.a.n[*d].node_id, name);
    }
    if errs > 0 { 1 } else { 0 }
}

// ---------------------------------------------------------- plate layout
fn dkey(p: &Project, el: usize) -> String {
    let n = &p.a.n[el];
    if n.tag == 't' {
        return format!("{}0", n.letter);
    }
    if n.tag == 'a' {
        return n.node_id.clone();
    }
    let par = n.parent.unwrap();
    let pid = if p.a.n[par].tag == 'a' {
        p.a.n[par].node_id.clone()
    } else {
        format!("{}0", p.a.n[par].letter)
    };
    format!("{}.{}{}", pid, n.tag, n.number.unwrap())
}

fn doc_plain(p: &Project, el: usize) -> String {
    p.a.n[el].doc.join(" ").replace("\\n", "\n")
}

fn md_code(s: &str) -> String {
    // `([^`]+)` -> <code>$1</code>, leftmost non-overlapping
    let b: Vec<char> = s.chars().collect();
    let mut o = String::new();
    let mut i = 0;
    while i < b.len() {
        if b[i] == '`' {
            if let Some(rel) = b[i + 1..].iter().position(|&c| c == '`') {
                if rel > 0 {
                    let inner: String = b[i + 1..i + 1 + rel].iter().collect();
                    o.push_str("<code>");
                    o.push_str(&inner);
                    o.push_str("</code>");
                    i += rel + 2;
                    continue;
                }
            }
        }
        o.push(b[i]);
        i += 1;
    }
    o
}

fn md_bold(s: &str) -> String {
    // \*\*(.+?)\*\* non-greedy
    let b: Vec<char> = s.chars().collect();
    let mut o = String::new();
    let mut i = 0;
    while i < b.len() {
        if i + 1 < b.len() && b[i] == '*' && b[i + 1] == '*' {
            let mut j = i + 2;
            let mut found = None;
            while j + 1 < b.len() + 1 {
                if j + 1 < b.len() && b[j] == '*' && b[j + 1] == '*' && j > i + 2 - 1 && j >= i + 3 {
                    found = Some(j);
                    break;
                }
                if j >= b.len() {
                    break;
                }
                j += 1;
            }
            if let Some(j) = found {
                let inner: String = b[i + 2..j].iter().collect();
                o.push_str("<strong>");
                o.push_str(&inner);
                o.push_str("</strong>");
                i = j + 2;
                continue;
            }
        }
        o.push(b[i]);
        i += 1;
    }
    o
}

fn md_em(s: &str) -> String {
    // (?<!\*)\*([^*]+)\*(?!\*)
    let b: Vec<char> = s.chars().collect();
    let mut o = String::new();
    let mut i = 0;
    while i < b.len() {
        if b[i] == '*' && (i == 0 || b[i - 1] != '*') {
            if let Some(rel) = b[i + 1..].iter().position(|&c| c == '*') {
                if rel > 0 {
                    let j = i + 1 + rel;
                    if j + 1 >= b.len() || b[j + 1] != '*' {
                        let inner: String = b[i + 1..j].iter().collect();
                        o.push_str("<em>");
                        o.push_str(&inner);
                        o.push_str("</em>");
                        i = j + 1;
                        continue;
                    }
                }
            }
        }
        o.push(b[i]);
        i += 1;
    }
    o
}

fn md_link(s: &str) -> String {
    // \[([^\]]+)\]\(([^)\s]+)\)
    let b: Vec<char> = s.chars().collect();
    let mut o = String::new();
    let mut i = 0;
    'outer: while i < b.len() {
        if b[i] == '[' {
            if let Some(rel) = b[i + 1..].iter().position(|&c| c == ']') {
                if rel > 0 {
                    let j = i + 1 + rel;
                    if j + 1 < b.len() && b[j + 1] == '(' {
                        let mut k = j + 2;
                        while k < b.len() && b[k] != ')' && !b[k].is_whitespace() {
                            k += 1;
                        }
                        if k < b.len() && b[k] == ')' && k > j + 2 {
                            let label: String = b[i + 1..j].iter().collect();
                            let url: String = b[j + 2..k].iter().collect();
                            o.push_str(&format!(
                                "<a href=\"{}\" target=\"_blank\">{}</a>", url, label));
                            i = k + 1;
                            continue 'outer;
                        }
                    }
                }
            }
        }
        o.push(b[i]);
        i += 1;
    }
    o
}

fn md_inline(text: &str) -> String {
    md_link(&md_em(&md_bold(&md_code(&esc(text)))))
}

fn doc_html(p: &Project, el: usize) -> String {
    let joined = p.a.n[el].doc.join(" ");
    joined
        .split("\\n")
        .map(|x| x.trim())
        .filter(|x| !x.is_empty())
        .map(|x| format!("<p>{}</p>", md_inline(x)))
        .collect()
}

fn effect_clean(a: &Arena, act: usize) -> bool {
    for &pi in &a.n[act].ports {
        if a.n[pi].tag == 'm' && a.n[pi].variant.is_none() {
            return false;
        }
    }
    a.n[act].children.iter().all(|&k| effect_clean(a, k))
}

fn plates_of(p: &Project, t: usize) -> Vec<(usize, Vec<usize>)> {
    let mut out = vec![(t, p.a.n[t].children.clone())];
    for ai in p.a.descendants(t) {
        if !p.a.n[ai].children.is_empty() {
            out.push((ai, p.a.n[ai].children.clone()));
        }
    }
    out
}

fn plate_id(p: &Project, t: usize, node: usize) -> String {
    if p.a.n[node].tag == 'a' {
        p.a.n[node].node_id.clone()
    } else {
        format!("{}0", p.a.n[t].letter)
    }
}

fn all_plates(p: &Project) -> Vec<(usize, usize, Vec<usize>)> {
    let mut out = Vec::new();
    for &t in &p.models {
        for (node, boxes) in plates_of(p, t) {
            out.push((t, node, boxes));
        }
    }
    out
}

fn port_route(p: &Project, pi: usize, t: usize) -> String {
    let n = &p.a.n[pi];
    if let Some(d) = n.link_dir {
        match n.link_target {
            Some(o) if p.a.n[o].model.is_some() => {
                let om = p.a.n[o].model.unwrap();
                return format!("{} {}:{}", d, p.a.n[om].letter, p.a.n[o].node_id);
            }
            _ => return format!("{} {}", d, n.link_path.join("|")),
        }
    }
    let tbl = if n.tag != 'o' { p.producers.get(&t) } else { p.consumers.get(&t) };
    let peers: Vec<usize> = tbl
        .and_then(|m| m.get(&n.name))
        .map(|v| v.iter().copied().filter(|&q| p.a.n[q].parent != n.parent).collect())
        .unwrap_or_default();
    if !peers.is_empty() {
        let mut ids: Vec<String> = peers
            .iter()
            .map(|&q| p.a.n[p.a.n[q].parent.unwrap()].node_id.clone())
            .collect::<HashSet<_>>()
            .into_iter()
            .collect();
        ids.sort();
        return format!("{}{}", if n.tag != 'o' { "from " } else { "to " }, ids.join(","));
    }
    String::new()
}

fn wrap_name(name: &str, width: usize, maxlines: usize) -> Vec<String> {
    let words: Vec<&str> = name.split_whitespace().collect();
    let mut lines: Vec<String> = Vec::new();
    let mut cur = String::new();
    for w in words {
        let t = if cur.is_empty() { w.to_string() } else { format!("{} {}", cur, w) };
        if t.chars().count() <= width || cur.is_empty() {
            cur = t;
        } else {
            lines.push(cur);
            cur = w.to_string();
        }
    }
    lines.push(cur);
    if lines.len() > maxlines {
        lines.truncate(maxlines);
        let last = lines.last_mut().unwrap();
        last.push_str("...");
    }
    lines
        .into_iter()
        .map(|l| {
            if l.chars().count() <= width {
                l
            } else {
                let cut: String = l.chars().take(width.saturating_sub(3)).collect();
                format!("{}...", cut)
            }
        })
        .collect()
}

struct Layout {
    pos: HashMap<usize, (i64, i64)>,
    bw: i64,
    #[allow(dead_code)]
    left: i64,
    #[allow(dead_code)]
    top: i64,
    w: i64,
    h: i64,
    ext_controls: Vec<String>,
    bh: i64,
}

fn layout_plate(p: &Project, t: usize, _node: usize, boxes: &[usize]) -> Layout {
    let maxname = boxes.iter().map(|&b| p.a.n[b].name.chars().count() as i64).max().unwrap_or(0);
    let bw = (maxname + 4).max(20).min(26);
    let mut in_labels: Vec<String> = Vec::new();
    let mut ext_controls: Vec<String> = Vec::new();
    let box_ids: HashSet<usize> = boxes.iter().copied().collect();
    for &b in boxes {
        for &pi in &p.a.n[b].ports {
            if p.a.n[pi].tag == 'i' {
                let r = port_route(p, pi, t);
                let lab = if r.is_empty() {
                    p.a.n[pi].name.clone()
                } else {
                    format!("{} ({})", p.a.n[pi].name, r)
                };
                in_labels.push(lab);
            }
            if p.a.n[pi].tag == 'c' {
                let name = p.a.n[pi].name.clone();
                let prod: Vec<usize> = p
                    .producers
                    .get(&t)
                    .and_then(|m| m.get(&name))
                    .map(|v| {
                        v.iter().copied()
                            .filter(|&q| box_ids.contains(&p.a.n[q].parent.unwrap()))
                            .collect()
                    })
                    .unwrap_or_default();
                if prod.is_empty() && !ext_controls.contains(&name) {
                    ext_controls.push(name);
                }
            }
        }
    }
    let left = if in_labels.is_empty() {
        8
    } else {
        (in_labels.iter().map(|s| s.chars().count() as i64).max().unwrap() + 4).max(8)
    };
    let top = 2 * ext_controls.len() as i64 + 2;
    let bh = BOX_H.max(2 + boxes.iter().map(|&b| {
        let ni = p.a.n[b].ports.iter().filter(|&&pi| p.a.n[pi].tag == 'i').count() as i64;
        let no = p.a.n[b].ports.iter().filter(|&&pi| p.a.n[pi].tag == 'o').count() as i64;
        ni.max(no)
    }).max().unwrap_or(0));
    let (hgap, vgap) = (12i64, 4i64);
    let mut pos = HashMap::new();
    for (i, &b) in boxes.iter().enumerate() {
        pos.insert(b, (left + i as i64 * (bw + hgap), top + i as i64 * (bh + vgap)));
    }
    let (lastx, lasty) = pos[boxes.last().unwrap()];
    let has_mech = boxes.iter().any(|&b| p.a.n[b].ports.iter().any(|&pi| p.a.n[pi].tag == 'm'));
    let w = (lastx + bw + 28).max(64);
    let h = lasty + bh + if has_mech { 5 } else { 2 } + 6;
    Layout { pos, bw, left, top, w, h, ext_controls, bh }
}

fn render_text_plate(p: &Project, t: usize, node: usize, boxes: &[usize], pageno: usize) -> String {
    let lay = layout_plate(p, t, node, boxes);
    let (pos, bw) = (&lay.pos, lay.bw);
    let bh_ = lay.bh;
    let mut grid: HashMap<(i64, i64), char> = HashMap::new();
    let put = |grid: &mut HashMap<(i64, i64), char>, r: i64, c: i64, s: &str| {
        for (k, ch) in s.chars().enumerate() {
            if c + k as i64 >= 0 {
                grid.insert((r, c + k as i64), ch);
            }
        }
    };
    for (ci, cname) in lay.ext_controls.iter().enumerate() {
        let row = 2 * ci as i64;
        let cons: Vec<usize> = boxes.iter().copied()
            .filter(|&b| p.a.n[b].ports.iter().any(|&pi| p.a.n[pi].tag == 'c' && p.a.n[pi].name == *cname))
            .collect();
        if cons.is_empty() {
            continue;
        }
        let cdrop = |b: usize| -> i64 {
            let ks: Vec<&String> = lay.ext_controls.iter()
                .filter(|c| p.a.n[b].ports.iter().any(|&pi| p.a.n[pi].tag == 'c' && p.a.n[pi].name == **c))
                .collect();
            let ki = ks.iter().position(|c| *c == cname).unwrap() as i64;
            let (x, _) = pos[&b];
            x + bw * (ki + 1) / (ks.len() as i64 + 1)
        };
        let mut cxs: Vec<i64> = cons.iter().map(|&b| cdrop(b)).collect();
        cxs.sort();
        put(&mut grid, row, cxs[0] + 2, cname);
        if cxs.len() > 1 {
            for c in cxs[0]..=cxs[cxs.len() - 1] {
                if !grid.contains_key(&(row + 1, c)) {
                    put(&mut grid, row + 1, c, "-");
                }
            }
        }
        for &b in &cons {
            let (_, y) = pos[&b];
            let cx = cdrop(b);
            for r in row + 1..y {
                if !grid.contains_key(&(r, cx)) {
                    put(&mut grid, r, cx, "|");
                }
            }
            put(&mut grid, y - 1, cx, "v");
        }
    }
    for &b in boxes {
        let (x, y) = pos[&b];
        put(&mut grid, y, x, &format!("+{}+", "-".repeat(bw as usize - 2)));
        for r in 1..bh_ - 1 {
            put(&mut grid, y + r, x, &format!("|{}|", " ".repeat(bw as usize - 2)));
        }
        put(&mut grid, y + bh_ - 1, x, &format!("+{}+", "-".repeat(bw as usize - 2)));
        for (j, l) in wrap_name(&p.a.n[b].name, bw as usize - 4, 2).iter().enumerate() {
            put(&mut grid, y + 1 + j as i64, x + 2, l);
        }
        let tagn = format!("{}{}", p.a.n[b].node_id, if p.a.n[b].children.is_empty() { "" } else { "*" });
        put(&mut grid, y + bh_ - 2, x + bw - 2 - tagn.chars().count() as i64, &tagn);
        let ins: Vec<usize> = p.a.n[b].ports.iter().copied().filter(|&pi| p.a.n[pi].tag == 'i').collect();
        for (k, &pi) in ins.iter().enumerate() {
            let r = y + 1 + (bh_ - 2 - ins.len() as i64) / 2 + k as i64;
            let rt = port_route(p, pi, t);
            let lab = if rt.is_empty() {
                p.a.n[pi].name.clone()
            } else {
                format!("{} ({})", p.a.n[pi].name, rt)
            };
            put(&mut grid, r, x - lab.chars().count() as i64 - 4, &format!("{} ->", lab));
        }
        let outs: Vec<usize> = p.a.n[b].ports.iter().copied().filter(|&pi| p.a.n[pi].tag == 'o').collect();
        for (k, &pi) in outs.iter().enumerate() {
            let r = y + 1 + (bh_ - 2 - outs.len() as i64) / 2 + k as i64;
            let rt = port_route(p, pi, t);
            let lab = if rt.is_empty() {
                p.a.n[pi].name.clone()
            } else {
                format!("{} ({})", p.a.n[pi].name, rt)
            };
            let arrow = if p.a.n[pi].variant.is_some() { ")-> " } else { "-> " };
            put(&mut grid, r, x + bw + 1, &format!("{}{}", arrow, lab));
        }
        let mechs: Vec<usize> = p.a.n[b].ports.iter().copied().filter(|&pi| p.a.n[pi].tag == 'm').collect();
        if !mechs.is_empty() {
            let cx = x + bw / 2;
            put(&mut grid, y + bh_, cx, "^");
            let lab = mechs.iter().map(|&pi| p.a.n[pi].name.clone()).collect::<Vec<_>>().join(", ");
            put(&mut grid, y + bh_ + 1, x + 2, &lab);
        }
    }
    let maxr = grid.keys().map(|&(r, _)| r).max().unwrap_or(0);
    let maxc = grid.keys().map(|&(_, c)| c).max().unwrap_or(0);
    let w = lay.w.max(maxc + 2);
    let mut lines: Vec<String> = Vec::new();
    for r in 0..lay.h.max(maxr + 1) {
        let line: String = (0..w).map(|c| grid.get(&(r, c)).copied().unwrap_or(' ')).collect();
        lines.push(line.trim_end().to_string());
    }
    let total = lines.iter().map(|l| l.chars().count() as i64).max().unwrap_or(0).max(64);
    let mid = (total - 26) as usize;
    let nid = plate_id(p, t, node);
    let mut title = p.a.n[node].name.clone();
    if title.chars().count() > mid - 2 {
        title = format!("{}...", title.chars().take(mid - 5).collect::<String>());
    }
    let num = format!("p.{}", pageno);
    let tb = vec![
        format!("+{}+{}+{}+", "-".repeat(11), "-".repeat(mid), "-".repeat(11)),
        format!("|{:<11}|{:<mid$}|{:<11}|", " NODE", " TITLE", " NUMBER", mid = mid),
        format!("|{:<11}|{:<mid$}|{:<11}|", format!(" {}", nid), format!(" {}", title), format!(" {}", num), mid = mid),
        format!("+{}+{}+{}+", "-".repeat(11), "-".repeat(mid), "-".repeat(11)),
    ];
    let mut all = lines;
    all.extend(tb);
    all.join("\n")
}

fn cmd_text(files: &[String]) -> i32 {
    let mut diags = Vec::new();
    let p = load_project(files, &mut diags, true);
    let (errs, _) = emit_diags(&diags, true);
    if errs > 0 {
        return 1;
    }
    let plates = all_plates(&p);
    println!("NODE INDEX{}p.1", " ".repeat(44));
    println!("{}", "-".repeat(64));
    for (i, (t, node, _)) in plates.iter().enumerate() {
        println!("  {:<10} {:<40} p.{}", plate_id(&p, *t, *node), p.a.n[*node].name, i + 2);
    }
    for (i, (t, node, boxes)) in plates.iter().enumerate() {
        println!("\u{c}");
        println!("{}", render_text_plate(&p, *t, *node, boxes, i + 2));
    }
    0
}

// --------------------------------------------------------------- svg
fn pyg(v: f64) -> String {
    if v == v.trunc() { format!("{}", v as i64) } else { format!("{}", v) }
}

fn pyfloat(v: f64) -> String {
    if v == v.trunc() { format!("{}.0", v as i64) } else { format!("{}", v) }
}

fn elbow(sx: i64, sy: i64, midx: i64, dyy: i64, dxx: i64) -> String {
    let r = 7f64;
    if sy == dyy {
        return format!("M{},{} H{}", sx, sy, dxx);
    }
    let vy: i64 = if dyy > sy { 1 } else { -1 };
    let hx2: i64 = if dxx >= midx { 1 } else { -1 };
    let mut rr = r
        .min((midx - sx).abs() as f64 / 2.0)
        .min((dyy - sy).abs() as f64 / 2.0);
    if dxx != midx {
        rr = rr.min((dxx - midx).abs() as f64 / 2.0);
    }
    if rr < 1.0 {
        return format!("M{},{} H{} V{} H{}", sx, sy, midx, dyy, dxx);
    }
    format!(
        "M{},{} H{} Q{},{} {},{} V{} Q{},{} {},{} H{}",
        sx, sy,
        pyg(midx as f64 - rr),
        midx, sy, midx, pyg(sy as f64 + vy as f64 * rr),
        pyg(dyy as f64 - vy as f64 * rr),
        midx, dyy, pyg(midx as f64 + hx2 as f64 * rr), dyy,
        dxx
    )
}

fn celbow(sx: i64, sy: i64, midx: i64, laney: i64, dropx: i64, boxtop: i64) -> String {
    let r = 7f64;
    let vy: i64 = if laney > sy { 1 } else { -1 };
    let hx: i64 = if dropx >= midx { 1 } else { -1 };
    let rr = r
        .min((midx - sx).abs() as f64 / 2.0)
        .min((laney - sy).abs() as f64 / 2.0)
        .min((dropx - midx).abs() as f64 / 2.0)
        .min((boxtop - laney).abs() as f64 / 2.0);
    if rr < 1.0 {
        return format!("M{},{} H{} V{} H{} V{}", sx, sy, midx, laney, dropx, boxtop);
    }
    format!(
        "M{},{} H{} Q{},{} {},{} V{} Q{},{} {},{} H{} Q{},{} {},{} V{}",
        sx, sy,
        pyg(midx as f64 - rr),
        midx, sy, midx, pyg(sy as f64 + vy as f64 * rr),
        pyg(laney as f64 - vy as f64 * rr),
        midx, laney, pyg(midx as f64 + hx as f64 * rr), laney,
        pyg(dropx as f64 - hx as f64 * rr),
        dropx, laney, dropx, pyg(laney as f64 + rr),
        boxtop
    )
}

fn xx(c: i64) -> i64 { c * CW + PAD }
fn yy(r: i64) -> i64 { r * CH + PAD }

fn svg_plate(p: &Project, t: usize, node: usize, boxes: &[usize], pageno: usize, rich: bool,
             pageof: Option<&HashMap<String, usize>>) -> String {
    let lay = layout_plate(p, t, node, boxes);
    let (pos, bw) = (&lay.pos, lay.bw);
    let bh_ = lay.bh;
    let dattr = |el: Option<usize>| -> String {
        match el {
            Some(e) if !p.a.n[e].doc.is_empty() && rich => {
                format!(" class=\"hasdoc\" data-doc=\"{}\"", dkey(p, e))
            }
            _ => String::new(),
        }
    };
    let dtitle = |el: Option<usize>| -> String {
        match el {
            Some(e) if !p.a.n[e].doc.is_empty() && !rich => {
                format!("<title>{}</title>", esc(&doc_plain(p, e)))
            }
            _ => String::new(),
        }
    };
    let box_ids: HashSet<usize> = boxes.iter().copied().collect();
    let route_tag = |pi: usize, rt: &str| -> String {
        if rt.is_empty() {
            return String::new();
        }
        if rich {
            if let (Some(pg), Some(tgt)) = (pageof, p.a.n[pi].link_target) {
                if let Some(a) = p.a.n[tgt].parent {
                    if p.a.n[a].tag == 'a' {
                        let par = p.a.n[a].parent.unwrap();
                        let pid = if p.a.n[par].tag == 'a' {
                            p.a.n[par].node_id.clone()
                        } else {
                            format!("{}0", p.a.n[par].letter)
                        };
                        if pg.contains_key(&pid) {
                            return format!(
                                "  <a href=\"#plate-{}\"><tspan fill=\"#1a5276\">[{}]</tspan></a>",
                                pid, esc(rt));
                        }
                    }
                }
            }
        }
        format!("  [{}]", esc(rt))
    };
    let width = xx(lay.w.max(64)) + PAD;
    let height = yy(lay.h + 4) + PAD;
    let mut o: Vec<String> = Vec::new();
    o.push(format!(
        "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"{}\" height=\"{}\" viewBox=\"0 0 {} {}\" font-family=\"IBM Plex Mono,monospace\">",
        width, height, width, height));
    o.push(format!("<rect width=\"{}\" height=\"{}\" fill=\"#fdfcf8\"/>", width, height));
    o.push("<defs><marker id=\"arr\" markerWidth=\"8\" markerHeight=\"8\" refX=\"7\" refY=\"3\" orient=\"auto\"><path d=\"M0,0 L7,3 L0,6 z\" fill=\"#222\"/></marker></defs>".into());
    let bctl: HashMap<usize, Vec<String>> = boxes.iter().map(|&b| {
        let mut names: Vec<String> = Vec::new();
        for &pi in &p.a.n[b].ports {
            if p.a.n[pi].tag == 'c' && !names.contains(&p.a.n[pi].name) {
                names.push(p.a.n[pi].name.clone());
            }
        }
        let bi = boxes.iter().position(|&x| x == b).unwrap() as i64;
        names.sort_by_key(|cname| {
            let prods: Vec<usize> = p.producers.get(&t)
                .and_then(|m| m.get(cname)).cloned().unwrap_or_default()
                .into_iter()
                .filter(|&q| {
                    let qp = p.a.n[q].parent.unwrap();
                    box_ids.contains(&qp) && qp != b
                })
                .collect();
            if prods.is_empty() {
                return (1i64, 0i64, 0i64);
            }
            let pr = prods[0];
            let prp = p.a.n[pr].parent.unwrap();
            let pi_ = boxes.iter().position(|&x| x == prp).unwrap() as i64;
            if pi_ < bi {
                let souts: Vec<usize> = p.a.n[prp].ports.iter().copied()
                    .filter(|&pp| p.a.n[pp].tag == 'o').collect();
                let oi = souts.iter().position(|&x| x == pr).unwrap() as i64;
                (0, pi_, -oi)
            } else {
                (2, pi_, 0)
            }
        });
        (b, names)
    }).collect();
    let cdrop = |b: usize, cname: &str| -> i64 {
        let ks = &bctl[&b];
        let (x, _) = pos[&b];
        xx(x) + bw * CW * (ks.iter().position(|c| c == cname).unwrap() as i64 + 1)
            / (ks.len() as i64 + 1)
    };
    for (ci, cname) in lay.ext_controls.iter().enumerate() {
        let row = 2 * ci as i64;
        let cons: Vec<usize> = boxes.iter().copied().filter(|b| bctl[b].contains(cname)).collect();
        if cons.is_empty() {
            continue;
        }
        let dp = cons.iter().flat_map(|&b2| p.a.n[b2].ports.iter().copied())
            .find(|&pi| p.a.n[pi].tag == 'c' && p.a.n[pi].name == *cname && !p.a.n[pi].doc.is_empty());
        let mut cxs: Vec<i64> = cons.iter().map(|&b| cdrop(b, cname)).collect();
        cxs.sort();
        let ybus = yy(row) + 16;
        o.push(format!("<text x=\"{}\" y=\"{}\" font-size=\"11\"{}{}>{}{}</text>",
                       cxs[0] + 5, yy(row) + 12, HALO, dattr(dp), esc(cname), dtitle(dp)));
        if cxs.len() > 1 {
            o.push(format!("<path d=\"M{},{} H{}\" fill=\"none\" stroke=\"#222\" stroke-width=\"1.1\"/>",
                           cxs[0], ybus, cxs[cxs.len() - 1]));
        }
        for &b in &cons {
            let (_, y) = pos[&b];
            let cx = cdrop(b, cname);
            o.push(format!("<path d=\"M{},{} V{}\" fill=\"none\" stroke=\"#222\" stroke-width=\"1.1\" marker-end=\"url(#arr)\"/>",
                           cx, ybus, yy(y)));
        }
    }
    // internal flows
    for &b in boxes {
        for &pi in &p.a.n[b].ports {
            if p.a.n[pi].tag != 'o' {
                continue;
            }
            let cons_list: Vec<usize> = p.consumers.get(&t)
                .and_then(|m| m.get(&p.a.n[pi].name)).cloned().unwrap_or_default();
            for q in cons_list {
                let qp = p.a.n[q].parent.unwrap();
                if !box_ids.contains(&qp) || qp == b {
                    continue;
                }
                if p.a.n[q].tag == 'c' {
                    let (sx0, sy0) = pos[&b];
                    let (_dx0, dy0) = pos[&qp];
                    let souts: Vec<usize> = p.a.n[b].ports.iter().copied()
                        .filter(|&pp| p.a.n[pp].tag == 'o').collect();
                    let oi = souts.iter().position(|&x| x == pi).unwrap() as i64;
                    let sx = xx(sx0 + bw);
                    let sy = yy(sy0) + (bh_ * CH) / 2 + (2 * oi - souts.len() as i64 + 1) * (CH / 2);
                    let dropx = cdrop(qp, &p.a.n[q].name);
                    let k = bctl[&qp].iter().position(|c| *c == p.a.n[q].name).unwrap() as i64;
                    let boxtop = yy(dy0);
                    let laney = boxtop - 22 - 12 * k;
                    let midx = sx + 20 + 6 * k;
                    o.push(format!("<path d=\"{}\" fill=\"none\" stroke=\"#222\" stroke-width=\"1.1\" marker-end=\"url(#arr)\"/>",
                                   celbow(sx, sy, midx, laney, dropx, boxtop)));
                    let fl = if !p.a.n[pi].doc.is_empty() { pi } else { q };
                    o.push(format!("<text x=\"{}\" y=\"{}\" font-size=\"9\" text-anchor=\"end\"{}{}>{}{}</text>",
                                   dropx - 4, laney - 4, HALO, dattr(Some(fl)),
                                   esc(&p.a.n[pi].name), dtitle(Some(fl))));
                    continue;
                }
                let (sx0, sy0) = pos[&b];
                let (dx0, dy0) = pos[&qp];
                let souts: Vec<usize> = p.a.n[b].ports.iter().copied()
                    .filter(|&pp| p.a.n[pp].tag == 'o').collect();
                let oi = souts.iter().position(|&x| x == pi).unwrap() as i64;
                let qins: Vec<usize> = p.a.n[qp].ports.iter().copied()
                    .filter(|&pp| p.a.n[pp].tag == 'i').collect();
                let sx = xx(sx0 + bw);
                let sy = yy(sy0) + (bh_ * CH) / 2 + (2 * oi - souts.len() as i64 + 1) * (CH / 2);
                let dxx = xx(dx0);
                let dyy = match qins.iter().position(|&x| x == q) {
                    Some(ix) => yy(dy0) + (bh_ * CH) / 2
                        + (2 * ix as i64 - qins.len() as i64 + 1) * (CH / 2),
                    None => yy(dy0 + 2) + CH / 2,
                };
                let midx = sx + 5 * CW;
                o.push(format!("<path d=\"{}\" fill=\"none\" stroke=\"#222\" stroke-width=\"1.1\" marker-end=\"url(#arr)\"/>",
                               elbow(sx, sy, midx, dyy, dxx)));
                let fl = if !p.a.n[pi].doc.is_empty() { pi } else { q };
                let ly = if sy != dyy { (sy + dyy).div_euclid(2) } else { sy - 5 };
                o.push(format!("<text x=\"{}\" y=\"{}\" font-size=\"9\"{}{}>{}{}</text>",
                               midx + 4, ly, HALO, dattr(Some(fl)),
                               esc(&p.a.n[pi].name), dtitle(Some(fl))));
            }
        }
    }
    for &b in boxes {
        let (x0, y0) = pos[&b];
        let (x, y) = (xx(x0), yy(y0));
        let (w, h) = (bw * CW, bh_ * CH);
        if rich && !p.a.n[b].children.is_empty() {
            o.push(format!("<a href=\"#plate-{}\">", p.a.n[b].node_id));
        }
        let bfill = if rich && effect_clean(&p.a, b) { "#f5faf1" } else { "#fff" };
        o.push(format!("<rect x=\"{}\" y=\"{}\" width=\"{}\" height=\"{}\" fill=\"{}\" stroke=\"#222\" stroke-width=\"1.6\"/>",
                       x, y, w, h, bfill));
        let nls = wrap_name(&p.a.n[b].name, bw as usize - 4, 3);
        let y0t = y + 26 - 7 * (nls.len() as i64 - 1);
        let spans: String = nls.iter().enumerate()
            .map(|(j, l)| format!("<tspan x=\"{}\" y=\"{}\">{}</tspan>",
                                  pyfloat(x as f64 + w as f64 / 2.0), y0t + 14 * j as i64, esc(l)))
            .collect();
        o.push(format!("<text font-size=\"12\" text-anchor=\"middle\"{}>{}{}</text>",
                       dattr(Some(b)), spans, dtitle(Some(b))));
        o.push(format!("<text x=\"{}\" y=\"{}\" font-size=\"10\" text-anchor=\"end\" fill=\"#555\">{}{}</text>",
                       x + w - 6, y + h - 8, p.a.n[b].node_id,
                       if p.a.n[b].children.is_empty() { "" } else { "*" }));
        if rich && !p.a.n[b].children.is_empty() {
            o.push("</a>".into());
        }
        let ins: Vec<usize> = p.a.n[b].ports.iter().copied().filter(|&pi| p.a.n[pi].tag == 'i').collect();
        for (k, &pi) in ins.iter().enumerate() {
            let py = y + h / 2 + (2 * k as i64 - ins.len() as i64 + 1) * (CH / 2);
            let rt = port_route(p, pi, t);
            if rt.starts_with("from ") {
                continue;
            }
            o.push(format!("<path d=\"M{},{} H{}\" fill=\"none\" stroke=\"#222\" stroke-width=\"1.1\" marker-end=\"url(#arr)\"/>",
                           x - 40, py, x));
            o.push(format!("<text x=\"{}\" y=\"{}\" font-size=\"9\" text-anchor=\"end\"{}{}>{}{}{}</text>",
                           x - 44, py + 3, HALO, dattr(Some(pi)), esc(&p.a.n[pi].name),
                           route_tag(pi, &rt), dtitle(Some(pi))));
        }
        let outs: Vec<usize> = p.a.n[b].ports.iter().copied().filter(|&pi| p.a.n[pi].tag == 'o').collect();
        for (k, &pi) in outs.iter().enumerate() {
            let py = y + h / 2 + (2 * k as i64 - outs.len() as i64 + 1) * (CH / 2);
            let rt = port_route(p, pi, t);
            if rt.starts_with("to ") {
                continue;
            }
            o.push(format!("<path d=\"M{},{} H{}\" fill=\"none\" stroke=\"#222\" stroke-width=\"1.1\" marker-end=\"url(#arr)\"/>",
                           x + w, py, x + w + 40));
            o.push(format!("<text x=\"{}\" y=\"{}\" font-size=\"9\"{}{}>{}{}{}</text>",
                           x + w + 44, py + 3, HALO, dattr(Some(pi)), esc(&p.a.n[pi].name),
                           route_tag(pi, &rt), dtitle(Some(pi))));
        }
        let mut vg_order: Vec<String> = Vec::new();
        let mut vgroups: HashMap<String, Vec<i64>> = HashMap::new();
        for (k, &pi) in outs.iter().enumerate() {
            if let Some(v) = p.a.n[pi].variant.clone() {
                let py = y + h / 2 + (2 * k as i64 - outs.len() as i64 + 1) * (CH / 2);
                if !vgroups.contains_key(&v) {
                    vg_order.push(v.clone());
                }
                vgroups.entry(v).or_default().push(py);
            }
        }
        for key in &vg_order {
            let pys = &vgroups[key];
            if pys.len() < 2 {
                continue;
            }
            let (y0, y1) = (pys.iter().min().unwrap() - 6, pys.iter().max().unwrap() + 6);
            let bx = x + w + 6;
            o.push(format!("<path d=\"M{},{} L{},{} L{},{} L{},{}\" fill=\"none\" stroke=\"#222\" stroke-width=\"1.3\"/>",
                           bx - 4, y0, bx, y0, bx, y1, bx - 4, y1));
            if key.chars().count() > 1 {
                o.push(format!("<text x=\"{}\" y=\"{}\" font-size=\"8\"{}>{}</text>",
                               bx + 3, (y0 + y1) / 2 + 3, HALO,
                               key.chars().nth(1).unwrap()));
            }
        }
        let mechs: Vec<usize> = p.a.n[b].ports.iter().copied().filter(|&pi| p.a.n[pi].tag == 'm').collect();
        if !mechs.is_empty() {
            let cx = x + w / 2;
            o.push(format!("<path d=\"M{},{} V{}\" fill=\"none\" stroke=\"#222\" stroke-width=\"1.1\" marker-end=\"url(#arr)\"/>",
                           cx, y + h + 30, y + h));
            let parts: String = mechs.iter().enumerate()
                .map(|(j, &pi)| format!("{}<tspan{}>{}{}</tspan>",
                                        if j > 0 { ", " } else { "" },
                                        dattr(Some(pi)), esc(&p.a.n[pi].name), dtitle(Some(pi))))
                .collect();
            o.push(format!("<text x=\"{}\" y=\"{}\" font-size=\"9\">{}</text>", cx + 4, y + h + 28, parts));
        }
    }
    let ty = height - 3 * CH;
    let nid = plate_id(p, t, node);
    o.push(format!("<rect x=\"0\" y=\"{}\" width=\"{}\" height=\"{}\" fill=\"#fff\" stroke=\"#222\"/>", ty, width, 3 * CH));
    o.push(format!("<line x1=\"{}\" y1=\"{}\" x2=\"{}\" y2=\"{}\" stroke=\"#222\"/>", 99, ty, 99, height));
    o.push(format!("<line x1=\"{}\" y1=\"{}\" x2=\"{}\" y2=\"{}\" stroke=\"#222\"/>", width - 99, ty, width - 99, height));
    o.push(format!("<text x=\"10\" y=\"{}\" font-size=\"10\">NODE</text>", ty + 16));
    o.push(format!("<text x=\"10\" y=\"{}\" font-size=\"12\">{}</text>", ty + 36, nid));
    o.push(format!("<text x=\"110\" y=\"{}\" font-size=\"10\">TITLE</text>", ty + 16));
    o.push(format!("<text x=\"110\" y=\"{}\" font-size=\"12\"{}>{}{}</text>",
                   ty + 36, dattr(Some(node)), esc(&p.a.n[node].name), dtitle(Some(node))));
    o.push(format!("<text x=\"{}\" y=\"{}\" font-size=\"10\">NUMBER</text>", width - 89, ty + 16));
    o.push(format!("<text x=\"{}\" y=\"{}\" font-size=\"12\">p.{}</text>", width - 89, ty + 36, pageno));
    o.push("</svg>".into());
    o.join("\n")
}

fn cmd_svg(nodeid: &str, files: &[String]) -> i32 {
    let mut diags = Vec::new();
    let p = load_project(files, &mut diags, true);
    let (errs, _) = emit_diags(&diags, true);
    if errs > 0 {
        return 1;
    }
    let plates = all_plates(&p);
    for (i, (t, node, boxes)) in plates.iter().enumerate() {
        if plate_id(&p, *t, *node) == nodeid {
            println!("{}", svg_plate(&p, *t, *node, boxes, i + 2, false, None));
            return 0;
        }
    }
    eprintln!("idef0: no plate {}", py_repr(nodeid));
    2
}

// --------------------------------------------------------------- html
const HTML_CSS: &str = "body{font-family:IBM Plex Mono,monospace;background:#eee;margin:0}\n.plate{background:#fff;margin:18px auto;padding:6px;box-shadow:0 1px 4px #0003;\nwidth:max-content;max-width:calc(100vw - 20px);overflow-x:auto;\npage-break-after:always}\nh1{font-size:16px;margin:18px}\ntable{border-collapse:collapse;margin:18px;background:#fff}\ntd,th{border:1px solid #999;padding:3px 9px;font-size:12px}\na{color:#1a5276}\n.nav{font-size:12px;padding:4px 8px;background:#f4f2ea;border-bottom:1px solid #ddd;\nposition:sticky;left:0}\n.nav a{text-decoration:none;margin-right:4px}\n.dim{color:#999}\ndetails.notes{font-size:12px;max-width:640px;padding:4px 8px;background:#fdfcf2;\nborder-bottom:1px solid #eee}\ndetails.notes p{margin:4px 0}\n.vp{overflow:hidden;touch-action:pan-x pan-y;cursor:grab}\n.vp:active{cursor:grabbing}\n.vp svg{display:block;transform-origin:0 0}\n.hasdoc{text-decoration:underline dotted 1.5px #6a994e;cursor:help}\nsvg a text{cursor:pointer}\nsvg a:hover rect{fill:#f5f9ee}\n#tip{position:fixed;display:none;z-index:9;max-width:340px;background:#fffbea;\nborder:1px solid #b7a;box-shadow:2px 3px 8px #0004;padding:2px 12px;\nfont-size:12.5px;line-height:1.45}\n#tip p{margin:8px 0}\n#tip code{background:#eee8d5;padding:0 3px}\n";

const HTML_JS: &str = "const tip=document.getElementById('tip');\nlet pin=null;\nfunction show(k,x,y){tip.innerHTML=DOCS[k]||'';tip.style.display='block';\n const r=tip.getBoundingClientRect();\n x=Math.min(x+14,innerWidth-r.width-8);y=Math.min(y+16,innerHeight-r.height-8);\n tip.style.left=Math.max(4,x)+'px';tip.style.top=Math.max(4,y)+'px';}\nfunction hide(){tip.style.display='none';pin=null;}\nconst canHover=matchMedia('(hover:hover)').matches;\ndocument.addEventListener('mousemove',e=>{if(!canHover||pin)return;\n const t=e.target.closest?e.target.closest('.hasdoc'):null;\n if(t)show(t.dataset.doc,e.clientX,e.clientY);else hide();});\ndocument.addEventListener('click',e=>{\n const t=e.target.closest?e.target.closest('.hasdoc'):null;\n if(t&&!t.closest('a')){\n  if(pin===t.dataset.doc){hide();}\n  else{pin=t.dataset.doc;show(pin,e.clientX,e.clientY);}\n  e.stopPropagation();}\n else if(!e.target.closest('#tip'))hide();});\n";

const PANZOOM_JS: &str = "document.querySelectorAll('.plate').forEach(pl=>{\n const vp=pl.querySelector('.vp'),rz=pl.querySelector('.vz');\n if(!vp)return;\n const g=vp.firstElementChild;\n let s=1,tx=0,ty=0,drag=null,moved=0,pd=0,pm=null,tmoved=0,lastTap=0;\n const P=new Map();\n const ap=()=>{g.style.transform='translate('+tx+'px,'+ty+'px) scale('+s+')';};\n const rst=()=>{s=1;tx=0;ty=0;ap();};\n const zoom=(f,x,y)=>{const ns=Math.min(8,Math.max(0.2,s*f));\n  tx=x-(x-tx)*ns/s;ty=y-(y-ty)*ns/s;s=ns;ap();};\n if(rz)rz.addEventListener('click',e=>{e.preventDefault();rst();});\n vp.addEventListener('dblclick',rst);\n vp.addEventListener('wheel',e=>{if(!e.ctrlKey)return;e.preventDefault();\n  const r=vp.getBoundingClientRect();\n  zoom(Math.exp(-e.deltaY*.002),e.clientX-r.left,e.clientY-r.top);},{passive:false});\n vp.addEventListener('pointerdown',e=>{\n  P.set(e.pointerId,[e.clientX,e.clientY]);\n  if(P.size===2){const a=[...P.values()];\n   pd=Math.hypot(a[0][0]-a[1][0],a[0][1]-a[1][1]);\n   pm=[(a[0][0]+a[1][0])/2,(a[0][1]+a[1][1])/2];tmoved=1;}\n  else if(e.pointerType==='mouse'&&e.button===1){e.preventDefault();\n   drag=[e.clientX,e.clientY];moved=0;}});\n vp.addEventListener('pointermove',e=>{\n  if(!P.has(e.pointerId))return;\n  P.set(e.pointerId,[e.clientX,e.clientY]);\n  if(P.size===2){e.preventDefault();\n   const a=[...P.values()],r=vp.getBoundingClientRect(),\n   d=Math.hypot(a[0][0]-a[1][0],a[0][1]-a[1][1]),\n   m=[(a[0][0]+a[1][0])/2,(a[0][1]+a[1][1])/2];\n   if(pd)zoom(d/pd,m[0]-r.left,m[1]-r.top);\n   tx+=m[0]-pm[0];ty+=m[1]-pm[1];pd=d;pm=m;ap();}\n  else if(drag){const dx=e.clientX-drag[0],dy=e.clientY-drag[1];\n   if(moved||Math.hypot(dx,dy)>4){moved=1;tx+=dx;ty+=dy;\n    drag=[e.clientX,e.clientY];ap();}}},{passive:false});\n const up=e=>{if(e.type==='pointercancel')tmoved=1;\n  P.delete(e.pointerId);\n  if(P.size<2)pd=0;\n  if(e.pointerType==='mouse')drag=null;\n  else if(P.size===0){const n=Date.now();\n   if(!tmoved&&n-lastTap<350)rst();\n   lastTap=n;tmoved=0;}};\n vp.addEventListener('pointerup',up);\n vp.addEventListener('pointercancel',up);\n vp.addEventListener('auxclick',e=>{if(moved){e.stopPropagation();e.preventDefault();moved=0;}},true);\n});\n";

fn json_str(s: &str) -> String {
    let mut o = String::from("\"");
    for c in s.chars() {
        match c {
            '"' => o.push_str("\\\""),
            '\\' => o.push_str("\\\\"),
            '\n' => o.push_str("\\n"),
            '\r' => o.push_str("\\r"),
            '\t' => o.push_str("\\t"),
            c if (c as u32) < 0x20 => o.push_str(&format!("\\u{:04x}", c as u32)),
            c if (c as u32) > 126 => {
                let cp = c as u32;
                if cp > 0xFFFF {
                    let v = cp - 0x10000;
                    o.push_str(&format!("\\u{:04x}\\u{:04x}", 0xD800 + (v >> 10), 0xDC00 + (v & 0x3FF)));
                } else {
                    o.push_str(&format!("\\u{:04x}", cp));
                }
            }
            c => o.push(c),
        }
    }
    o.push('"');
    o
}

fn plate_of_port(p: &Project, pi: usize, pageof: &HashMap<String, usize>) -> Option<String> {
    let a = p.a.n[pi].parent?;
    if p.a.n[a].tag == 't' {
        return None;
    }
    let par = p.a.n[a].parent.unwrap();
    let pid = if p.a.n[par].tag == 'a' {
        p.a.n[par].node_id.clone()
    } else {
        format!("{}0", p.a.n[par].letter)
    };
    if pageof.contains_key(&pid) {
        Some(pid)
    } else {
        None
    }
}

fn cmd_html(files: &[String]) -> i32 {
    let mut diags = Vec::new();
    let p = load_project(files, &mut diags, true);
    let (errs, _) = emit_diags(&diags, true);
    if errs > 0 {
        return 1;
    }
    let plates = all_plates(&p);
    let mut pageof: HashMap<String, usize> = HashMap::new();
    for (i, (t, node, _)) in plates.iter().enumerate() {
        pageof.insert(plate_id(&p, *t, *node), i + 2);
    }
    let mut docs_order: Vec<String> = Vec::new();
    let mut docs: HashMap<String, String> = HashMap::new();
    for &t in &p.models {
        let mut els = vec![t];
        els.extend(p.a.descendants(t));
        for el in els {
            if !p.a.n[el].doc.is_empty() {
                let k = dkey(&p, el);
                if !docs.contains_key(&k) {
                    docs_order.push(k.clone());
                }
                docs.insert(k, doc_html(&p, el));
            }
            for &pi in &p.a.n[el].ports {
                if !p.a.n[pi].doc.is_empty() {
                    let k = dkey(&p, pi);
                    if !docs.contains_key(&k) {
                        docs_order.push(k.clone());
                    }
                    docs.insert(k, doc_html(&p, pi));
                }
            }
        }
    }
    let mut out: Vec<String> = Vec::new();
    out.push(format!("<!doctype html><meta charset='utf-8'><meta name='viewport' content='width=device-width,initial-scale=1'><title>IDEF0 drawing set</title><style>{}</style>", HTML_CSS));
    out.push("<h1 id='top'>IDEF0 drawing set &mdash; p.1: node index and interface table</h1>".into());
    out.push("<table><tr><th>NODE</th><th>TITLE</th><th>NUMBER</th></tr>".into());
    for (i, (t, node, _)) in plates.iter().enumerate() {
        let pid = plate_id(&p, *t, *node);
        let k = dkey(&p, *node);
        let cls = if docs.contains_key(&k) {
            format!(" class='hasdoc' data-doc='{}'", k)
        } else {
            String::new()
        };
        out.push(format!(
            "<tr><td><a href='#plate-{}'>{}</a></td><td{}>{}</td><td><a href='#plate-{}'>p.{}</a></td></tr>",
            pid, pid, cls, esc(&p.a.n[*node].name), pid, i + 2));
    }
    out.push("</table>".into());
    out.push("<table><tr><th>SOURCE</th><th>DEST</th><th>FLOW</th></tr>".into());
    for (s, d, name) in &p.rows {
        let sp = plate_of_port(&p, *s, &pageof);
        let dp = plate_of_port(&p, *d, &pageof);
        let sc = match sp {
            Some(x) => format!("<a href='#plate-{}'>{}</a>", x, p.a.n[*s].node_id),
            None => p.a.n[*s].node_id.clone(),
        };
        let dc = match dp {
            Some(x) => format!("<a href='#plate-{}'>{}</a>", x, p.a.n[*d].node_id),
            None => p.a.n[*d].node_id.clone(),
        };
        out.push(format!("<tr><td>{}</td><td>{}</td><td>{}</td></tr>", sc, dc, esc(name)));
    }
    out.push("</table>".into());
    for (i, (t, node, boxes)) in plates.iter().enumerate() {
        let pid = plate_id(&p, *t, *node);
        out.push(format!("<div class='plate' id='plate-{}'>", pid));
        let mut nav: Vec<String> = vec!["<a href='#top'>&#8962; index</a>".into()];
        if p.a.n[*node].tag == 'a' {
            let par = p.a.n[*node].parent.unwrap();
            let up = if p.a.n[par].tag == 'a' {
                p.a.n[par].node_id.clone()
            } else {
                format!("{}0", p.a.n[par].letter)
            };
            nav.push(format!("<a href='#plate-{}'>&#8593; {}</a>", up, up));
        } else {
            nav.push("<span class='dim'>top plate</span>".into());
        }
        nav.push("<a href='javascript:history.back()'>&#8592; back</a>".into());
        nav.push("<a href='javascript:history.forward()'>fwd &#8594;</a>".into());
        nav.push("<a href='#' class='vz' title='reset pan/zoom (ctrl+scroll or pinch to zoom, middle-drag to pan)'>&#10530; reset</a>".into());
        nav.push(format!("<span class='dim'>{} &middot; p.{}</span>", pid, i + 2));
        out.push(format!("<div class='nav'>{}</div>", nav.join(" &middot; ")));
        if !p.a.n[*node].doc.is_empty() {
            out.push(format!("<details class='notes'><summary>notes: {}</summary>{}</details>",
                             esc(&p.a.n[*node].name), doc_html(&p, *node)));
        }
        out.push("<div class='vp'>".into());
        out.push(svg_plate(&p, *t, *node, boxes, i + 2, true, Some(&pageof)));
        out.push("</div>".into());
        out.push("</div>".into());
    }
    let payload: String = format!("{{{}}}",
        docs_order.iter()
            .map(|k| format!("{}: {}", json_str(k), json_str(&docs[k])))
            .collect::<Vec<_>>().join(", "))
        .replace("</", "<\\/");
    out.push(format!("<div id='tip'></div><script>const DOCS={};\n{}{}</script>", payload, HTML_JS, PANZOOM_JS));
    println!("{}", out.join("\n"));
    0
}

// --------------------------------------------------------------- fmt
fn cmd_fmt(mode: Option<&str>, write: bool, files: &[String]) -> i32 {
    let mut diags = Vec::new();
    let p = load_project(files, &mut diags, false);
    let (errs, _) = emit_diags(&diags, true);
    if errs > 0 {
        eprintln!("fmt: refusing to rewrite files with errors");
        return 1;
    }
    for f in files {
        let recs = &p.doc.iter().find(|(fname, _)| fname == f).unwrap().1;
        let mut lines: Vec<String> = Vec::new();
        for rec in recs.iter() {
            let node = match rec.node {
                Some(n) => n,
                None => {
                    lines.push(rec.raw.clone());
                    continue;
                }
            };
            let n = &p.a.n[node];
            let sfx = match mode {
                Some("number") => {
                    if n.tag == 't' {
                        n.letter.to_string()
                    } else {
                        n.number.unwrap().to_string()
                    }
                }
                Some("auto") => "#".to_string(),
                _ => {
                    if n.suffix.is_empty() {
                        "#".to_string()
                    } else {
                        n.suffix.clone()
                    }
                }
            };
            let mut line = format!("{}{}{}{} {}", " ".repeat(n.indent), n.tag,
                                   n.variant.clone().unwrap_or_default(), sfx, n.name);
            if let Some(d) = n.link_dir {
                line.push_str(&format!(" {} {}", d, n.link_path.join("|")));
            }
            if let Some(t) = &n.trail {
                line.push_str(&format!("  {}", t));
            }
            lines.push(line);
        }
        let text = format!("{}\n", lines.join("\n"));
        if write {
            fs::write(f, &text).unwrap();
        } else {
            if files.len() > 1 {
                println!("==> {} <==", f);
            }
            print!("{}", text);
        }
    }
    if write {
        println!("fmt: rewrote {} file(s) [{}]", files.len(), mode.unwrap_or("normalize"));
    }
    0
}

// --------------------------------------------------------------- main
fn main() {
    let argv: Vec<String> = env::args().collect();
    if argv.len() < 2 {
        println!("{}", USAGE);
        std::process::exit(2);
    }
    let cmd = argv[1].as_str();
    let args: Vec<String> = argv[2..].to_vec();
    let code = match cmd {
        "lint" => cmd_lint(&args),
        "dump" => cmd_dump(&args),
        "links" => cmd_links(&args),
        "text" => cmd_text(&args),
        "html" => cmd_html(&args),
        "svg" => {
            if args.is_empty() {
                eprintln!("usage: idef0 svg NODE FILE...");
                std::process::exit(2);
            }
            cmd_svg(&args[0], &args[1..])
        }
        "fmt" => {
            let mut mode: Option<&str> = None;
            let mut write = false;
            let mut files: Vec<String> = Vec::new();
            for a in &args {
                match a.as_str() {
                    "--number" => mode = Some("number"),
                    "--auto" => mode = Some("auto"),
                    "--write" => write = true,
                    _ => files.push(a.clone()),
                }
            }
            cmd_fmt(mode, write, &files)
        }
        _ => {
            eprintln!("idef0: unknown command {}", py_repr(cmd));
            println!("{}", USAGE);
            std::process::exit(2);
        }
    };
    std::process::exit(code);
}
