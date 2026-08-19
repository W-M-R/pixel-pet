#!/usr/bin/env python3
"""校验一份待注入的译文 JSON，再喂给 xcstrings_tool.py inject。

为什么需要它：手写 251 × 18 条译文时，肉眼漏检是必然的。实测已经吃过一次
——日语文件里混进了韩文「오프」。占位符漏改、复数类别给错同理。

检查项：
  1. key 集合与英文原文完全一致（不多不少）
  2. 占位符个数/类型/位置编号与英文原文一致（复数各类别分别比对）
  3. 复数结构对齐（英文是 plural 的必须是 plural，反之亦然）
  4. 复数类别符合该语言的 CLDR 要求（ru/pl 四类、ar 六类、CJK 只 other…）
  5. **字符集串味**：译文里混入不属于该语言的文字（韩文混进日语等）
  6. 空值 / 仍是英文原文未翻译（宽松提示，专有名词可豁免）

用法：
    python3 check_translation.py <en_source.json> <lang.json>
退出码非 0 表示有硬错误，不应注入。
"""
import json, re, sys, unicodedata

# 各语言需要的 CLDR 复数类别（与 skill references/languages.md 一致）
PLURAL_CATS = {
    'en': {'one','other'}, 'de': {'one','other'}, 'fr': {'one','other'},
    'es': {'one','other'}, 'it': {'one','other'}, 'pt-BR': {'one','other'},
    'hi': {'one','other'}, 'tr': {'one','other'}, 'nl': {'one','other'},
    'sv': {'one','other'},
    'ru': {'one','few','many','other'}, 'pl': {'one','few','many','other'},
    'ar': {'zero','one','two','few','many','other'},
    'zh-Hans': {'other'}, 'zh-Hant': {'other'}, 'ja': {'other'},
    'ko': {'other'}, 'th': {'other'}, 'id': {'other'}, 'vi': {'other'},
}

# 每种语言「不该出现」的字符区间。只查最容易串味的几类脚本：
# 韩文谚文、日文假名、CJK 汉字、西里尔、阿拉伯、天城体、泰文。
SCRIPTS = {
    'hangul':   (r'[\uac00-\ud7af\u1100-\u11ff\u3130-\u318f]', 'ko'),
    'kana':     (r'[\u3040-\u309f\u30a0-\u30ff]',               'ja'),
    'cyrillic': (r'[\u0400-\u04ff]',                            'ru'),
    'arabic':   (r'[\u0600-\u06ff\u0750-\u077f]',               'ar'),
    'devanagari':(r'[\u0900-\u097f]',                           'hi'),
    'thai':     (r'[\u0e00-\u0e7f]',                            'th'),
}
# 允许使用汉字的语言（日语用汉字、中文当然用）
HANZI_OK = {'zh-Hans','zh-Hant','ja'}
HANZI = r'[\u4e00-\u9fff]'

# ⚠️ 不要把空格放进 flag 类里。C 的 `% d` 确实合法，但本工程从不这么写，
# 而德语等排版规范要求「90 % halten」这种 % 后跟空格 —— 带空格的话
# `% ha` 会被当成 `%a`（十六进制浮点）匹配上，误报成占位符不一致。
# 这里只收本工程真实用到的形态：%@ %lld %+lld %1$@ %2$lld %%。
SPEC = re.compile(r'%(?:\d+\$)?[+\-0#]?[0-9]*(?:\.[0-9]+)?(?:ll|l|hh|h|z|q)?[@dioxXufFeEgGcsp%]')

def phs(s: str):
    """提取占位符（忽略 %% 字面百分号），排序后比较——语序可变，集合不可变。"""
    return sorted(m.group(0) for m in SPEC.finditer(s) if m.group(0) != '%%')

def main():
    if len(sys.argv) != 3:
        sys.exit(__doc__)
    src = json.load(open(sys.argv[1], encoding='utf-8'))
    blob = json.load(open(sys.argv[2], encoding='utf-8'))
    if len(blob) != 1:
        sys.exit(f"期望顶层只有一个语言键，实际 {list(blob)}")
    lang = next(iter(blob))
    tr = blob[lang]

    errs, warns = [], []

    missing = [k for k in src if k not in tr]
    extra   = [k for k in tr if k not in src]
    if missing: errs.append(f"缺 {len(missing)} 个 key: {missing[:6]}")
    if extra:   errs.append(f"多 {len(extra)} 个 key: {extra[:6]}")

    want_cats = PLURAL_CATS.get(lang)
    for k, v in tr.items():
        if k not in src: continue
        s = src[k]
        # --- 结构对齐 ---
        if isinstance(s, dict):
            if not (isinstance(v, dict) and 'plural' in v):
                errs.append(f"{k}: 英文是复数，译文却不是 plural 结构"); continue
            got = set(v['plural'])
            if want_cats and got != want_cats:
                errs.append(f"{k}: {lang} 复数类别应为 {sorted(want_cats)}，实际 {sorted(got)}")
            base = s.get('other') or s.get('one') or ''
            for cat, val in v['plural'].items():
                if not val.strip():
                    errs.append(f"{k}[{cat}]: 空值"); continue
                if phs(val) != phs(base):
                    errs.append(f"{k}[{cat}]: 占位符 {phs(val)} != 英文 {phs(base)}")
            vals = list(v['plural'].values())
        else:
            if isinstance(v, dict):
                errs.append(f"{k}: 英文非复数，译文却是 plural 结构"); continue
            if not v.strip():
                errs.append(f"{k}: 空值"); continue
            if phs(v) != phs(s):
                errs.append(f"{k}: 占位符 {phs(v)} != 英文 {phs(s)}")
            vals = [v]

        # --- 字符集串味 ---
        for val in vals:
            for name, (pat, owner) in SCRIPTS.items():
                if owner == lang: continue
                # 日语允许假名+汉字；中文允许汉字
                if name == 'kana' and lang == 'ja': continue
                m = re.search(pat, val)
                if m:
                    errs.append(f"{k}: 混入 {name}({owner}) 字符 {m.group(0)!r} -> {val!r}")
            if lang not in HANZI_OK and re.search(HANZI, val):
                m = re.search(HANZI, val)
                errs.append(f"{k}: 混入汉字 {m.group(0)!r} -> {val!r}")

        # --- 未翻译提示（专有名词会误报，只作 warning）---
        if isinstance(s, str) and isinstance(v, str) and v == s and len(s) > 3:
            warns.append(f"{k}: 与英文完全相同 {s!r}")

    print(f"[{lang}] key={len(tr)}  错误={len(errs)}  提示={len(warns)}")
    for e in errs[:40]: print("  ✗", e)
    if len(errs) > 40: print(f"  … 另有 {len(errs)-40} 条")
    for w in warns[:10]: print("  ·", w)
    if len(warns) > 10: print(f"  … 另有 {len(warns)-10} 条提示")
    return 1 if errs else 0

if __name__ == '__main__':
    sys.exit(main())
