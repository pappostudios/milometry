"""
Difficulty rater v2 for Milometry vocabulary files.
Rates each word 1-10 (1=easiest, 10=hardest).

Unit number is intentionally NOT used — it reflects curriculum order, not word
difficulty.  All signals come from the words and their translations directly.

English signals:
  - Membership in ~1,500-word VERY_COMMON frequency list (strongest signal)
  - Word length
  - Academic / rare suffixes
  - Syllable count (vowel-group proxy)
  - Multi-word phrases: average score of parts + small bump

Hebrew signals:
  - Consonant count of the term (niqqud stripped; takes first variant if slashes present)
  - Multi-word / idiomatic phrase (spaces in term)
  - Translation word count and average Hebrew word length (conceptual density)
  - Multiple distinct meanings in translation (semicolons / commas)
"""

import json, re

# ─── Common English words (~1 500 most frequent) ─────────────────────────────
VERY_COMMON = {
    'a','about','above','across','act','add','after','again','against','age',
    'ago','all','also','always','am','among','an','and','any','are','area',
    'as','ask','at','away','back','be','because','been','before','between',
    'big','both','but','by','call','can','carry','cause','change','children',
    'city','close','come','could','country','cut','day','did','different','do',
    'does','done','down','during','each','early','earth','end','even','every',
    'example','eye','face','fact','fall','far','few','find','first','follow',
    'food','for','form','from','full','get','give','go','good','great','grow',
    'hand','hard','has','have','he','help','her','here','high','him','his',
    'home','how','however','idea','if','important','in','into','is','it','its',
    'just','keep','kind','know','large','last','later','learn','leave','let',
    'life','light','like','line','list','little','live','long','look','low',
    'main','make','man','many','may','me','mean','men','might','more','most',
    'move','much','must','my','name','need','never','new','next','night','no',
    'not','now','of','off','often','old','on','once','one','only','open','or',
    'other','our','out','over','own','part','people','place','plan','play',
    'point','put','real','right','room','run','said','same','saw','say','see',
    'seem','set','she','should','show','side','small','so','some','something',
    'sometimes','soon','state','still','story','study','such','take','tell',
    'than','that','the','their','them','then','there','these','they','thing',
    'think','this','those','though','thought','three','through','time','to',
    'together','too','took','toward','try','turn','two','under','until','up',
    'us','use','very','want','was','water','way','we','well','went','were',
    'what','when','where','which','while','who','will','with','without','word',
    'work','world','would','write','year','you','young','your',
    'able','already','although','another','anything','appear','around','base',
    'become','begin','below','better','body','book','both','bring','build',
    'case','certain','check','class','clear','common','complete','continue',
    'course','cover','create','decide','deep','describe','design','develop',
    'direct','drive','enough','ever','everything','feel','felt','fine','fire',
    'five','force','four','free','front','happen','hear','heart','hold',
    'hour','house','human','including','increase','inside','interest','keep',
    'known','land','late','lead','less','letter','level','likely','list','live',
    'local','look','lost','love','made','matter','measure','mind','money',
    'month','morning','natural','nothing','number','object','once','order',
    'outside','paper','past','piece','plant','point','power','present','problem',
    'process','provide','public','question','quickly','read','ready','reason',
    'remember','result','return','road','rule','school','second','short','since',
    'six','size','society','someone','sort','sound','south','space','speak',
    'special','stand','start','stop','story','street','strong','surface','sure',
    'system','table','talk','ten','term','test','today','together','told',
    'tree','true','type','usually','value','various','view','visit','voice',
    'wait','walk','watch','week','whether','whole','wide','woman','women',
    'answer','arms','ball','bird','black','blue','board','break','bright',
    'brown','came','camp','care','cent','chair','chance','charge','choice',
    'circle','cold','color','come','cost','count','dark','dead','deal','death',
    'draw','dream','dress','drop','east','effect','else','enter','equal','even',
    'evening','except','expect','experience','explain','eyes','fast','fear',
    'feet','field','fight','fill','final','floor','fly','foot','found','frame',
    'fresh','game','garden','gate','gave','general','glass','gold','gone',
    'ground','group','guess','hair','half','hall','happy','heat','heavy','hill',
    'hole','hope','horse','hot','hotel','hunt','image','inch','instead','iron',
    'island','join','jump','king','kitchen','lake','law','lay','leg','listen',
    'load','lone','lord','loss','map','mark','match','meet','metal','middle',
    'mile','milk','mirror','model','modern','mountain','mouth','music','near',
    'neck','nose','note','oil','orange','pain','paint','pair','park','party',
    'path','pay','pick','picture','pig','pink','pipe','plate','pocket','pool',
    'poor','pretty','price','pride','prime','print','prize','probably',
    'product','program','project','pull','push','rain','raise','rate','reach',
    'red','relation','remain','rent','replace','report','rest','rice','rich',
    'ride','ring','rise','river','rock','roll','roof','rose','rough','round',
    'royal','safe','sail','sand','save','seat','sell','send','sense','serve',
    'seven','shade','shake','shall','shape','share','sharp','sheet','ship',
    'shoe','shoot','shop','shore','shot','shoulder','sight','sign','simple',
    'sing','skin','sky','sleep','slide','slow','smile','snow','soil','solid',
    'speed','spend','spin','spirit','split','spread','spring','square','stage',
    'star','stay','steam','steel','step','stick','stone','store','storm',
    'strange','stream','stretch','string','stroke','stuck','style','sugar',
    'suit','sum','sun','supply','swim','tail','tall','taste','teach','tear',
    'teeth','thank','thick','thin','throw','tight','tire','title','tone',
    'tooth','touch','town','track','trade','train','trust','truth','twist',
    'uncle','union','unit','upper','usual','valley','village','warm','wash',
    'waste','wave','wear','weight','west','wheat','wheel','white','wild','win',
    'wind','wing','wire','wish','wood','wool','worth','yard','yellow','yet',
}

ACADEMIC_SUFFIXES = [
    'tion','sion','ment','ity','ness','ance','ence','ism','ist','ize','ise',
    'ful','less','ous','ive','al','ic','ical','ify','ary','ery','ory','ogy',
    'phy','omy','ate','ent','ant','ible','able',
]

RARE_SUFFIXES = [
    'acity','ocity','osity','ility','ibility','ality','uality','ivity',
    'ousness','iousness','fulness','lessness','ification','alization',
    'isation','ization','ential','aneous',
]


# ─── Hebrew helpers ──────────────────────────────────────────────────────────

def strip_niqqud(word: str) -> str:
    """Remove Hebrew diacritics: niqqud (U+05B0–U+05C7) and cantillation (U+0591–U+05AF)."""
    return ''.join(c for c in word if not (0x0591 <= ord(c) <= 0x05C7))


def count_heb_consonants(word: str) -> int:
    """Count Hebrew consonant letters (alef–tav, U+05D0–U+05EA) after stripping niqqud."""
    return sum(1 for c in strip_niqqud(word) if 'א' <= c <= 'ת')


def canonical_heb_term(term: str) -> str:
    """
    For terms with slash-separated variants like 'בּוּרְסְקִי / בּוּרְסְקַאי',
    return only the first variant (shortest / most common form).
    """
    return term.split('/')[0].strip()


def heb_translation_complexity(translation: str) -> float:
    """
    Score how complex a Hebrew-language translation string is.  Returns 0.0–4.0.

    Signals:
      - Number of words in the definition (more = harder concept)
      - Semicolons: clearly separates multiple distinct meanings (strong signal)
      - Commas: alternative forms or light listing
      - Average consonant count of the definition words (denser words = harder)
    """
    words = translation.strip().split()
    n = len(words)

    # Multiple distinct meanings via semicolons → significantly harder word
    semi_bonus  = translation.count(';') * 1.4
    comma_bonus = translation.count(',') * 0.25

    # Average Hebrew consonant length of the definition words
    avg_cons = sum(count_heb_consonants(w) for w in words) / max(1, n)
    density_bonus = max(0.0, (avg_cons - 3.0) * 0.18)

    raw = n * 0.22 + semi_bonus + comma_bonus + density_bonus
    return min(4.0, raw)


# ─── Hebrew difficulty ────────────────────────────────────────────────────────

def hebrew_difficulty(word: str, translation: str) -> int:
    """Rate a Hebrew vocabulary word 1–10, unit-agnostic."""

    # Use first variant only (ignore slash alternatives)
    primary = canonical_heb_term(word)

    # Consonant count of the primary term form
    n_cons = count_heb_consonants(primary)

    # Length → score mapping (shorter = more common = easier)
    if n_cons <= 2:   len_score = -2.0
    elif n_cons == 3: len_score = -1.3
    elif n_cons == 4: len_score = -0.5
    elif n_cons == 5: len_score =  0.3
    elif n_cons == 6: len_score =  1.1
    elif n_cons == 7: len_score =  1.9
    elif n_cons <= 9: len_score =  2.6
    else:             len_score =  3.2   # long idioms

    # Bonus for multi-word phrases (e.g., "הלך שבי", "אזר מתניו")
    phrase_words = len(primary.split())
    phrase_score = 0.6 * max(0, phrase_words - 1)

    # Translation complexity
    trans_score = heb_translation_complexity(translation)

    # Baseline 3.5 so 2-consonant single-meaning words reach ~2
    raw = 3.5 + len_score * 0.70 + trans_score * 1.55 + phrase_score
    return max(1, min(10, round(raw)))


# ─── English helpers ─────────────────────────────────────────────────────────

def _score_single_english(w: str) -> float:
    """Raw float score for one English token (no clamping)."""
    if w in VERY_COMMON:
        return 1.0 if len(w) <= 4 else 2.0

    score = 4.5  # neutral baseline for uncommon words

    # Length
    l = len(w)
    if l <= 3:    score -= 2.5
    elif l <= 5:  score -= 1.2
    elif l <= 7:  score  = score          # neutral
    elif l <= 9:  score += 1.2
    elif l <= 12: score += 2.3
    else:         score += 3.8

    # Rare / academic suffixes
    matched_rare = False
    for suf in RARE_SUFFIXES:
        if w.endswith(suf):
            score += 2.5
            matched_rare = True
            break
    if not matched_rare:
        for suf in ACADEMIC_SUFFIXES:
            if w.endswith(suf) and len(w) > len(suf) + 2:
                score += 1.2
                break

    # Syllable complexity (vowel groups as proxy)
    vowel_groups = len(re.findall(r'[aeiou]+', w))
    score += max(0.0, (vowel_groups - 2) * 0.5)

    return score


def english_difficulty(word: str) -> int:
    """Rate an English vocabulary word 1–10, unit-agnostic.  Handles phrases."""
    parts = word.lower().strip().split()
    if len(parts) == 1:
        return max(1, min(10, round(_score_single_english(parts[0]))))

    # Multi-word phrase: average component scores + small bump for complexity
    avg = sum(_score_single_english(p) for p in parts) / len(parts)
    return max(1, min(10, round(avg + 0.5)))


# ─── Main ─────────────────────────────────────────────────────────────────────

def process_file(input_path: str, output_path: str, lang: str):
    print(f"\n{'='*60}")
    print(f"Processing {input_path}")
    with open(input_path, encoding='utf-8') as f:
        data = json.load(f)

    words  = data['words']
    rated  = []
    dist   = {i: 0 for i in range(1, 11)}

    for w in words:
        if lang == 'english':
            diff = english_difficulty(w['term'])
        else:
            diff = hebrew_difficulty(w['term'], w['translation'])

        entry = dict(w)
        entry['difficulty'] = diff
        rated.append(entry)
        dist[diff] += 1

    output = {'words': rated}
    with open(output_path, 'w', encoding='utf-8') as f:
        json.dump(output, f, ensure_ascii=False, indent=2)

    print(f"Written {len(rated)} words -> {output_path}")
    print(f"Distribution: {dist}")

    # Spot-check: 3 samples per difficulty band
    print("\nSpot-check (3 samples per difficulty):")
    by_diff: dict = {}
    for w in rated:
        by_diff.setdefault(w['difficulty'], []).append(w)
    for d in sorted(by_diff):
        samples = by_diff[d][:3]
        terms = ', '.join(s['term'] for s in samples)
        print(f"  [{d}] {terms}")


if __name__ == '__main__':
    import os, sys, io
    # Force UTF-8 output so Hebrew prints correctly on Windows
    sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding='utf-8')

    base = os.path.join(os.path.dirname(os.path.abspath(__file__)), 'assets')

    process_file(
        os.path.join(base, 'hebrew.json'),
        os.path.join(base, 'hebrew_with_difficulty.json'),
        'hebrew',
    )
    process_file(
        os.path.join(base, 'english.json'),
        os.path.join(base, 'english_with_difficulty.json'),
        'english',
    )

    print("\nDone! New files saved in assets/")
