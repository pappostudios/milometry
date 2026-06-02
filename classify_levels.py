"""
5-Level vocabulary classifier for Milometry — Hebrew + English

Hebrew levels:
  1 Basic       — Modern everyday Hebrew; news, podcasts, daily speech
  2 Medium      — Quality journalism, popular literature, standard psychometric
  3 High        — Academic/literary; Mishna or Talmud origin; educated speakers hesitate
  4 Very High   — Archaic; rarely spoken; Aramaic expressions; psychometric traps
  5 Extreme     — Biblical hapax, ancient trades/tools, deceptive near-synonyms

English levels:
  1 Basic       — In the ~1500-word VERY_COMMON frequency list
  2 Medium      — Common academic/connective vocabulary
  3 High        — Standard SAT-level words
  4 Very High   — Advanced academic; rare suffixes; 3+ syllables
  5 Extreme     — Obscure, archaic, or highly deceptive words
"""

import json, re, os

# ─── Shared Hebrew helpers ────────────────────────────────────────────────────

def strip_niqqud(s: str) -> str:
    return ''.join(c for c in s if not (0x0591 <= ord(c) <= 0x05C7))

def canonical(term: str) -> str:
    """Strip niqqud + take first variant before '/'."""
    return strip_niqqud(term.split('/')[0]).strip()

def count_heb_cons(word: str) -> int:
    return sum(1 for c in strip_niqqud(word) if 'א' <= c <= 'ת')


# ═══════════════════════════════════════════════════════════════════════════════
#  HEBREW CLASSIFICATION
# ═══════════════════════════════════════════════════════════════════════════════

# ── Level 1: Common modern Hebrew ─────────────────────────────────────────────
# Words any educated Israeli hears in daily news, podcasts, or conversation.
HEBREW_L1 = {
    # Modern loanwords fully absorbed into Hebrew
    'אקרן','דיאלוג','מונולוג','ביוגרפיה','לויאלי','אמפירי','היפותטי',
    'אובייקטיבי','קוהרנטי','אוטוקרטיה','מונוגמיה','פוליגמיה','ביגמיה',
    'מונותאיזם','כרונולוגי','ספורדי','אופורטוניזם','הדוניזם','וולגרי',
    'ארכאי','ארכיפלג','דואלי','קלישאה','קלישה','שרלטן','תסמין','מסרון',
    'קמין','פרמיירה','ארכיאולוגיה','אטמוספירה','פרוצדורה','טקטיקה',
    # Common modern Hebrew verbs (news/speech)
    'הסלים','הכחיש','הגר','הדליף','הלך שולל','הונה','סיכל','הלאים','הפריט',
    'הוקיע','הזים','קטרג','גינה',
    # Common nouns/adjectives in news
    'גינוי','קריסה','מחלוקת','שביתת נשק','מפורז','חתרנות','קדימון','שרב',
    'ילודה','שדרה','אומדן','אפיק','תמורה','תמלול','שכתוב','שינן',
    # Common expressions everyone knows
    'יצא מכליו','שגעון גדלות','שמחה לאיד','מפח נפש','קורת רוח',
    'אחיזת עיניים','תוחלת חיים','הלך שולל','אבן בוחן','אבן פינה',
    'אבן שואבת',
    # Common everyday adjectives/adverbs
    'שכיח','יהיר','ארעי','בשוגג','אפוא',
    # Common emotions/psychology
    'תשוקה','כיסופים','דכדוך','שמחה לאיד','נרגן','זבן',
    # Common legal/civic
    'סנגור','קטגור','הדרן','שינן',
    # Common modern words
    'קלישאה','פולמוס','כאוס','כאוטי','בדיעבד','ארעי','שרלטן',
    'לקוני','מאוס','חרד','בשורה','נאור','צחצוח חרבות',
    'תרעומת','תוחלת חיים','שדרה','ילודה','גניזה',
}

# ── Level 2: Standard psychometric — quality journalism / popular literature ──
# Words that educated Israelis know but wouldn't use in casual speech.
HEBREW_L2 = {
    # Common expressions / phrases found in Haaretz-level journalism
    'בשורה','בגפו','לא בכדי','כלאחר יד','בהנף יד','תרעומת',
    'שאון','נחשול','נוגה','לקוני','שכך','הקיץ','מבוסם',
    'בית מרחץ','בית נכות','בית נתיבות','שמאי','מגבית',
    'נרפה','בושש','שוקק חיים','נאור','איתן','ייתן',
    'מאוס','פורה','נכלם','מחלוקת','ואדי','שילהי',
    'עסיסי','ענף','קובלנה','שכוך','שירבוט','מלוקי',
    'זחוח','נהנתן','ישיש','סורר','נטמע','דמעות תנין',
    'יד רוחצת יד','עמד על טיבו','הקץ על','הסביר פנים',
    'גמילה','תל','ניכוש','כרך','דיכדוך','מחאה','מחה',
    'הדיח','דובב','שלוה','שיסה','קרקר','שדוד','שדוף',
    'הבליג','הגיר','נגף','נהמה','מפלצת','כישלון','אחריות',
    'יהירות','נגיד','מרות','תביעה','עריריות','נגן',
    'הסה','גאות','שפל','מצה','קטן אמונה','שוחר',
    'מוסר כלייות','כבד לשון','כבד פה','ירד לסוף דעתו',
    'נחמה','דממה','שהייה','מגרה','ידיד נפש','שמחה',
    'חוצפה','ניכור','ניחוח','צלול','עכור','כמוש',
    'רדוד','נהיה','סתום','רפה','גרוע','אלוף','עולל',
    'זאטוט','ניצן','שרברב','כישרון','שרעפים','הגיג',
    'מחשבה','יגאל','ביצוע','הקים','הטביע','שיקף',
    'אמד','הישג','צנוע','נמוך רוח','ענווה','ענו','ענווה',
    'יראה','יאוש','נלאה','לאות','גאווה','יהב','נכסים',
    'נגר','זלג','ניצב','נישא','מרפסת','חצר','גדרות',
    'מכשיר','מסמך','מדריך','קטגוריה','שיטה','אמצעי',
    'שלב','תהליך','מדיניות','יעד','מסגרת','גורם',
    'מגמה','תחום','מרכיב','פיתוח','ניהול','ביצוע',
    'השפעה','תוצאה','תופעה','מציאות','מצב','מעמד',
    # Common literary words not exotic enough for Level 3
    'אגד','אגל','אבוקה','אמה','פלג','שלוה','הידהד',
    'חלחול','שיטוח','ריב','קרע','פתי','זמורה',
    'חבורה','מעש','נקיק','צחיח','שאיפה','קרחת',
    'ציר','עדי','להב','לחי','חיץ','אנקה','מחווה',
}

# ── Level 4: Archaic / Aramaic / psychometric traps ───────────────────────────
# Rarely used in modern spoken Hebrew; require active memorization.
HEBREW_L4 = {
    # Aramaic-origin words and expressions (Talmudic Hebrew)
    'נהיר','גילופין','בגילופין','בפומבי','בפומבי','לדידו',
    'ינוקא','זוטא','פורתא','לעילא ולעילא','ברישי גלי','ברישי גלי',
    'מלגו','מלגו ומלבר','רישא','סייפא','בעלמא','דברים בעלמא',
    'בר מינן','גושפנקא','אגב אורחא','לאשורו','יש דברים בגו',
    'בין המצרים','בין השיטין','מיטת סדום','בית מרזח','נחמה פורתא',
    'הדום','טבולה ראסה','בין הערביים',
    # Archaic biblical idioms that educated Israelis recognise but wouldn't use
    'נחבא אל הכלים','הדום','הלך שבי','העלה ארוכה','הטיל את חיתו',
    'זרה אבק בעיניים','זרה חול בעיניים','הדיר שינה מעיניו',
    'הוקיר רגליו','הדיר רגליו','פסח על שתי הסעיפים',
    'גדש את הסאה','הגדיש את הסאה','חרף נפשו',
    'ישב על המדוכה','הקשה את לבו','הקשה את ערפו',
    'שלח יד בנפשו','רפה את ידיו','רפיון ידיים','אמץ את ידיו',
    'ימים יגידו', # add more known phrases
    'כבד לשון', 'כבד פה','כתמול שלשום','לא שזפתו עין',
    'יד רוחצת יד','יש בלבו עליו','ירד לסוף דעתו',
    'קשר לו כתרים','עמד מנגד','עמד מן הצד',
    'עמד על דעתו','נפל על אזניים ערלות','הפליג ב','הפליג בשבחו',
    'שאט נפש','בין השמשות','בין הערביים',
    'בר שפיטה','חדל פרעון','חילופי גברי',
    'הכה גלים','הכה שורש','הכה על חטא',
    'ירד לטמיון','היה חרד','נים ולא נים',
    # Archaic or rare words used as traps
    'נדן','הסה','כיסוי','מעדר','שברב',
    'בין הערביים','בין השמשות',
    # Specific archaic terms often tested
    'בעטיו','בעוד מועד','לכתחילה',
    'לא בכדי','כלאחר יד','בהנף יד','בהנף יד',
    'חסר ישע','מוג לב','עולל','עלה נידף',
    'אין ידו משגת',
}

# ── Level 5: Extremely rare / biblical / ancient trades ───────────────────────
# Would trip even educated native speakers; ultra-specific ancient items.
HEBREW_L5 = {
    # Ancient pottery / weaving / textile
    'אבניים','כישור','נול','מנפטה','מנפטה',
    # Ancient agricultural tools
    'מגל','מזמרה','מכוש','מורג','מקצרה','חרמש','גרזן','קרדם',
    # Ancient vessels / containers
    'מרחשת','מחבצה','קסת','נאד','כיכר','ייחידת משקל עתיקה',
    # Ancient crafts / professions
    'בורסקי','בורסקאי','בורסי','סתת','סתת','קושש','בלן',
    # Ancient oil / grain / wine production
    'בית בד','גורן','גת',
    # Biblical / rare items
    'איצטבה','אפריון','יערה','כסיה','כסיה','אמתחת','אשפה',
    'מרצע','מקצועה','מפסלת','חישור','סדן','משוורת','מוקש',
    # Extremely rare biblical words
    'אמה','אבניים','גז','גזה','תלם','שבלת','עלי',
    'מכמורת','כברה','מממגורה','ממגורה','מתבן','שוקת','עביט',
    'כף מחט','קוף המחט','עגלון','סייס','בוצר','מסיק',
    'בציר','עורה','רחיים','שבת','נושה','מלק',
    # Archaic words almost nobody knows
    'חרמש','מרצע','אבן משחזת','קרקפת','נקיבה',
    'גבר','שכוי','תיש','בכר','נאקה',
    'חוק','זב חוטם','זבד','זוט','גפת','דכי',
    'קיתון','כפיס','כפיר','לביא','שחל',
    'עפרות זהב','מחצבה','חבשה','מוץ',
    'ערדליים','פלצור','רתמה','דרבן','חריט',
    'מוד','מרבק','מרקחת','שפת',
    # Extremely archaic idioms / phrases
    'נפל על אזניים ערלות','פכר את ידיו','פכר את אצבעותיו',
    'משענת קנה רצוץ','אבן רחיים על צווארו',
    'לא שזפתו עין','הפליא בו את מכותיו',
    'אבד עליו הכלח','נחבא אל הכלים',
    'הלך רכיל','בור סוד שאינו מאבד טיפה',
    'הלך שבי','גדם','מראשית','ראשית',
}

# ── Translation-based scoring for Level 2 vs 3 ───────────────────────────────

def heb_trans_score(translation: str) -> float:
    """Return 0–4 complexity score for a Hebrew translation string."""
    words = translation.strip().split()
    n = len(words)
    semi  = translation.count(';') * 1.4
    comma = translation.count(',') * 0.2
    avg_c = sum(count_heb_cons(w) for w in words) / max(1, n)
    density = max(0.0, (avg_c - 3.0) * 0.18)
    return min(4.0, n * 0.22 + semi + comma + density)


def classify_hebrew(term: str, translation: str) -> int:
    """Return level 1–5 for a Hebrew vocabulary word."""
    key = canonical(term)

    if key in HEBREW_L1:
        return 1
    if key in HEBREW_L5:
        return 5
    if key in HEBREW_L4:
        return 4
    if key in HEBREW_L2:
        return 2

    # ── Automatic Level 5 detectors ──────────────────────────────────────────
    # Multi-word phrase with 4+ words often = rare biblical idiom
    phrase_words = len(key.split())
    if phrase_words >= 4:
        # Only bump to 5 if translation also signals complexity
        trans = heb_trans_score(translation)
        if trans >= 2.0:
            return 5
        return 4

    # ── Automatic Level 4 detectors ──────────────────────────────────────────
    # Aramaic function words embedded in the term
    aramaic_markers = ['ינוקא','זוטא','פורתא','עלמא','לדידי','ברישי',
                       'מלגו','מלגאו','גברי','גברא','כפרא','רישא','סייפא',
                       'בפומבי','נהיר']
    for marker in aramaic_markers:
        if marker in key:
            return 4

    # ── Heuristic scoring for Levels 2–3 ─────────────────────────────────────
    n_cons   = count_heb_cons(canonical(term))
    trans_sc = heb_trans_score(translation)

    # Short words with simple translations lean toward Level 2
    if n_cons <= 3:
        return 2
    if n_cons == 4 and trans_sc < 1.8:
        return 2
    if n_cons <= 5 and trans_sc < 0.7:
        return 2

    return 3


# ═══════════════════════════════════════════════════════════════════════════════
#  ENGLISH CLASSIFICATION
# ═══════════════════════════════════════════════════════════════════════════════

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

# Level 5 English — extremely rare, archaic, or deceptive
ENGLISH_L5 = {
    'loquacious','perspicacious','sycophantic','obsequious','pusillanimous',
    'mellifluous','susurrus','diaphanous','ephemeral','ineffable','sesquipedalian',
    'tendentious','truculent','vituperative','recondite','abstruse','arcane',
    'inscrutable','opprobrious','obstreperous','querulous','ignominious',
    'inimical','perfidious','mendacious','inveterate','intransigent',
    'recalcitrant','impecunious','imperturbable','inexorable','enigmatic',
    'insipid','immutable','inimitable','impudent','imperious','implacable',
    'impervious','impetuous','impromptu','inchoate','incongruous','incontrovertible',
    'indolent','inducement','ineradicable','ingenuous','iniquitous',
    'intrepid','invidious','laconic','limpid','lissome','lugubrious',
    'malleable','mendacious','mercurial','meretricious','moribund',
    'munificent','nefarious','obdurate','obfuscate','oblique','obtuse',
    'onerous','ominous','opprobrium','panacea','panegyric','parsimonious',
    'pellucid','penitent','peregrinate','perfidy','petulant','pique',
    'placate','plausible','plenitude','plethora','poignant','portentous',
    'pragmatic','precipitate','precocious','predilection','proclivity',
    'prodigious','profligate','propitious','prudent','pugnacious',
    'punctilious','redolent','remonstrate','reprobate','reticent',
    'sagacious','salient','sanguine','sardonic','scrupulous','serene',
    'sycophant','taciturn','tangential','tenuous','terse','timorous',
    'tortuous','tractable','transient','trite','truculent','turbid',
    'turgid','ubiquitous','umbrage','unequivocal','vacillate','venerate',
    'veracity','verbose','vestige','vicarious','vindicate','vitiate',
    'voluble','wanton','zealous','acrimony','alacrity','amalgamate',
    'ameliorate','anachronism','anathema','animosity','anomaly','antipathy',
    'antithesis','apathy','appease','arduous','articulate','ascertain',
    'assiduous','assuage','astute','audacious','augment','austere',
    'avaricious','belligerent','benevolent','benign','besmirch','bilk',
    'blatant','brazen','cajole','callous','candor','capricious','catharsis',
    'caustic','censure','chastise','circumspect','clandestine','coerce',
    'cogent','compunction','conciliate','condescend','confound','conjecture',
    'conscientious','conspicuous','contrite','convoluted','copious','corroborate',
    'credulity','culpable','cupidity','cursory','debilitate','deferential',
    'deprecate','deride','despondent','didactic','diffident','digress',
    'diligent','discern','discerning','disdain','disinterested','disparage',
    'disparate','dissemble','dissipate','dogmatic','dubious','duplicity',
    'ebullient','eccentric','elicit','eloquent','emulate','enervate','equivocal',
    'erudite','esoteric','euphemism','exacerbate','exigent','expedient',
    'fervid','flippant','foment','fortuitous','fractious','frivolous',
    'frugal','garrulous','gratuitous','gullible','hapless','hedonism',
    'heresy','hubris','hypocrite','idiosyncrasy','impasse','impeccable',
    'imprudent','inadvertent','incisive','incorrigible','indefatigable',
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


def _raw_english(w: str) -> float:
    """Raw float score (not clamped) for a single English token."""
    if w in VERY_COMMON:
        return 1.0 if len(w) <= 4 else 2.0
    if w in ENGLISH_L5:
        return 10.0

    score = 4.5
    l = len(w)
    if   l <= 3:  score -= 2.5
    elif l <= 5:  score -= 1.2
    elif l <= 9:  score += 0.0
    elif l <= 12: score += 2.0
    else:         score += 3.8

    matched_rare = False
    for suf in RARE_SUFFIXES:
        if w.endswith(suf):
            score += 2.5; matched_rare = True; break
    if not matched_rare:
        for suf in ACADEMIC_SUFFIXES:
            if w.endswith(suf) and len(w) > len(suf) + 2:
                score += 1.2; break

    vowels = len(re.findall(r'[aeiou]+', w))
    score += max(0.0, (vowels - 2) * 0.5)
    return score


def classify_english(word: str) -> int:
    """Return level 1–5 for an English vocabulary word or phrase."""
    parts = word.lower().strip().split()
    if len(parts) == 1:
        raw = _raw_english(parts[0])
    else:
        avg = sum(_raw_english(p) for p in parts) / len(parts)
        raw = avg + 0.5

    # Map raw score to level
    if raw <= 2.5:   return 1
    elif raw <= 4.5: return 2
    elif raw <= 6.5: return 3
    elif raw <= 8.5: return 4
    else:            return 5


# ═══════════════════════════════════════════════════════════════════════════════
#  FILE PROCESSING
# ═══════════════════════════════════════════════════════════════════════════════

def process(input_path: str, output_dir: str, lang: str):
    print(f"\n{'='*60}")
    print(f"Processing {input_path}  [{lang}]")

    with open(input_path, encoding='utf-8') as f:
        words = json.load(f)['words']

    buckets = {i: [] for i in range(1, 6)}
    dist    = {i: 0  for i in range(1, 6)}

    for w in words:
        if lang == 'hebrew':
            lvl = classify_hebrew(w['term'], w['translation'])
        else:
            lvl = classify_english(w['term'])

        entry = dict(w)
        entry['level'] = lvl
        buckets[lvl].append(entry)
        dist[lvl] += 1

    print(f"Distribution: {dist}")

    os.makedirs(output_dir, exist_ok=True)
    prefix = 'heb' if lang == 'hebrew' else 'eng'

    for lvl in range(1, 6):
        fname = os.path.join(output_dir, f'{prefix}_level_{lvl}.json')
        with open(fname, 'w', encoding='utf-8') as f:
            json.dump({'level': lvl, 'language': lang, 'words': buckets[lvl]},
                      f, ensure_ascii=False, indent=2)
        print(f"  Level {lvl}: {len(buckets[lvl])} words -> {fname}")

    # Spot-check
    print("\n  Spot-check (3 samples per level):")
    for lvl in range(1, 6):
        samples = buckets[lvl][:3]
        if samples:
            terms = ', '.join(s['term'] for s in samples)
            print(f"    [L{lvl}] {terms}")


if __name__ == '__main__':
    import sys, io
    sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding='utf-8')

    base = os.path.join(os.path.dirname(os.path.abspath(__file__)), 'assets')
    out  = os.path.join(base, 'levels')

    process(os.path.join(base, 'hebrew.json'),  out, 'hebrew')
    process(os.path.join(base, 'english.json'), out, 'english')

    print("\nDone! Level files saved in assets/levels/")
