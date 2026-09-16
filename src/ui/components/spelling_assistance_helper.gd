class_name SpellingAssistanceHelper
extends RefCounted

## Reliable General-Purpose Shared Inline Spelling Assistance Engine for StudyCenterHub
## Uses full-dictionary lexicon loading, smart stemming/inflection normalizers,
## possessive/contraction handling, candidate ranking, inline red underline marking,
## and right-click / control-click contextual corrections without interrupting typing.

static var _valid_word_set: Dictionary = {}
static var _candidate_word_list: Array = []
static var _ignored_words: Dictionary = {}
static var _is_dict_loaded: bool = false

const SUGGESTION_MAP = {
	"restraaunt": "restaurant",
	"restaraunt": "restaurant",
	"restraunt": "restaurant",
	"resturant": "restaurant",
	"definately": "definitely",
	"recieve": "receive",
	"recieved": "received",
	"recieving": "receiving",
	"tommorow": "tomorrow",
	"tomorow": "tomorrow",
	"freinds": "friends",
	"teh": "the",
	"taht": "that",
	"wiht": "with",
	"hvae": "have",
	"seperate": "separate",
	"seperated": "separated",
	"seperating": "separating",
	"calender": "calendar",
	"adress": "address",
	"wierd": "weird",
	"occured": "occurred",
	"occurance": "occurrence",
	"beleive": "believe",
	"helt": "help",
	"accommodate": "accommodate",
	"acommodate": "accommodate",
	"recomended": "recommended",
	"recomend": "recommend",
	"embarass": "embarrass",
	"privlege": "privilege",
	"privelege": "privilege",
	"maintanance": "maintenance",
	"untill": "until",
	"truely": "truly",
	"achive": "achieve",
	"goverment": "government",
	"enviroment": "environment",
	"independant": "independent",
	"succesful": "successful",
	"superintendant": "superintendent"
}

const COMMON_ENGLISH_WORDS = [
	"a", "about", "above", "accept", "accepted", "access", "account", "accounts", "accurate", "act",
	"action", "actions", "active", "activity", "actual", "actually", "add", "added", "adding", "addition",
	"address", "addresses", "administration", "advance", "after", "again", "against", "agenda", "agree",
	"agreed", "ahead", "alert", "alerts", "all", "allow", "allowed", "allowing", "allows", "almost",
	"along", "already", "also", "always", "am", "amount", "an", "and", "another", "answer",
	"answered", "answers", "any", "anyone", "anything", "anyway", "app", "appear", "appeared", "appears",
	"application", "apply", "appointment", "appointments", "appreciaate", "appreciate", "appreciated",
	"approach", "approve", "approved", "april", "archive", "archived", "are", "area", "areas", "around",
	"arrangements", "arrival", "arrive", "arrived", "art", "article", "as", "ask", "asked", "asking",
	"asks", "assigned", "assignee", "assignment", "assist", "assistance", "assistant", "associate",
	"associated", "at", "atendance", "attach", "attached", "attachment", "attendance", "august", "auto",
	"automatic", "available", "average", "away", "back", "background", "bad", "bar", "base", "based",
	"basic", "basically", "be", "beautiful", "because", "become", "becomes", "been", "before", "begin",
	"beginning", "begins", "begun", "behalf", "behind", "being", "belief", "believe", "believed",
	"below", "beside", "besides", "best", "better", "between", "beyond", "big", "bill", "billing",
	"birthday", "birthdays", "bit", "black", "blue", "board", "body", "book", "booked", "booking",
	"books", "both", "box", "boxes", "boy", "boys", "brand", "break", "brief", "briefly", "bring",
	"brings", "broad", "brother", "brothers", "brought", "build", "building", "buildings", "built",
	"bulletin", "business", "busy", "but", "button", "buttons", "buy", "by", "calendar", "calendars",
	"call", "called", "calling", "calls", "came", "camper", "campers", "can", "cancel", "canceled",
	"cancelled", "cancelling", "candidate", "capabilities", "capability", "card", "cards", "care",
	"careful", "carefully", "carry", "case", "cases", "cat", "catch", "category", "cause", "center",
	"centers", "central", "certain", "certainly", "change", "changed", "changes", "changing", "channel",
	"channels", "character", "characters", "charge", "chart", "check", "checked", "checking", "checkin",
	"checkins", "checks", "child", "children", "choice", "choose", "chose", "chosen", "church", "churches",
	"city", "claim", "class", "classes", "classic", "classification", "classroom", "classrooms", "clean",
	"clear", "clearly", "cleared", "click", "clicked", "clicks", "client", "clients", "clock", "close",
	"closed", "closely", "closing", "code", "codes", "collect", "collected", "collection", "college",
	"color", "colors", "column", "columns", "come", "comes", "coming", "command", "comment", "comments",
	"common", "communication", "communications", "community", "company", "complete", "completed",
	"completing", "completion", "complex", "component", "components", "compose", "composer", "computer",
	"concept", "concern", "concerned", "condition", "conference", "confirm", "confirmation", "confirmed",
	"connect", "connected", "connection", "consent", "consider", "considered", "consist", "consistent",
	"contact", "contacted", "contacts", "contain", "contained", "contains", "content", "contents",
	"context", "continue", "continued", "continues", "contract", "control", "controls", "conversation",
	"conversations", "convert", "converted", "coordinator", "coordinators", "copy", "copied", "core",
	"corner", "correct", "corrected", "correction", "corrections", "correctly", "cost", "costs", "could",
	"count", "counter", "counting", "counts", "country", "couple", "course", "courses", "cover", "coverage",
	"covered", "covering", "create", "created", "creates", "creating", "creation", "credential", "credentials",
	"credit", "criteria", "critical", "current", "currently", "custom", "customer", "cut", "daily",
	"dashboard", "data", "database", "date", "dates", "day", "days", "decline", "declined", "deep",
	"default", "define", "defined", "definitely", "definition", "degree", "delete", "deleted", "delivering",
	"delivery", "demand", "department", "depend", "deposit", "depth", "description", "design", "designation",
	"designed", "desire", "desk", "desktop", "detail", "detailed", "details", "detect", "detected",
	"detection", "determine", "determined", "develop", "developer", "development", "device", "devices",
	"dialog", "dialogs", "did", "different", "difficult", "digital", "direct", "direction", "directly",
	"directory", "disable", "disabled", "dispatched", "display", "displayed", "displays", "distance",
	"district", "division", "do", "dock", "document", "documents", "documentation", "does", "doing",
	"done", "door", "double", "doubt", "down", "download", "downloaded", "draft", "drive", "drop",
	"dropdown", "due", "during", "each", "earlier", "early", "easy", "easily", "edit", "edited",
	"editing", "editor", "editors", "education", "educational", "effect", "effective", "effort",
	"eight", "either", "element", "elements", "eligible", "eligibility", "else", "email", "emails",
	"emergency", "emojis", "empower", "enable", "enabled", "enables", "enabling", "end", "ended",
	"ending", "ends", "energy", "engage", "engaged", "engagement", "engine", "engineering", "english",
	"enhance", "enhanced", "enhancement", "enjoy", "enough", "enroll", "enrolled", "enrollment", "enter",
	"entered", "entering", "entire", "entirely", "entry", "environment", "equal", "equipment", "error",
	"errors", "escape", "especially", "essential", "establish", "established", "estimate", "event",
	"events", "ever", "every", "everyone", "everything", "exact", "exactly", "example", "examples",
	"excellent", "except", "exception", "exchange", "excited", "exclude", "excluded", "execute",
	"executed", "executing", "execution", "existing", "exit", "expand", "expanded", "expect", "expected",
	"experience", "expert", "expiration", "expired", "expires", "explain", "explained", "export",
	"exported", "exporting", "express", "expression", "extend", "extended", "extension", "extra",
	"eye", "face", "fact", "factor", "fail", "failed", "failing", "failure", "failures", "fall",
	"false", "family", "far", "fast", "father", "fear", "feature", "features", "february", "feed",
	"feedback", "feeds", "feel", "feeling", "fees", "feet", "few", "field", "fields", "file", "files",
	"fill", "filled", "film", "final", "finally", "finance", "financial", "find", "finding", "finds",
	"fine", "finish", "finished", "first", "fit", "five", "fix", "fixed", "fixes", "flag", "flagged",
	"flags", "flat", "flexible", "flexibility", "flip", "flow", "focus", "focused", "folder", "folders",
	"follow", "followed", "following", "follows", "font", "fonts", "food", "for", "force", "forefront",
	"foreign", "form", "format", "formats", "formatted", "formatting", "formed", "former", "forms",
	"formula", "forth", "forward", "found", "foundation", "four", "free", "friday", "friend", "friends",
	"from", "front", "full", "fully", "function", "functional", "functionality", "functions", "fund",
	"funding", "funds", "further", "future", "gain", "gained", "gap", "gaps", "garden", "gate",
	"gateway", "gathering", "gave", "general", "generally", "generate", "generated", "generating",
	"generation", "generator", "genuine", "get", "gets", "getting", "girl", "girls", "give", "given",
	"gives", "giving", "glass", "global", "go", "goal", "goals", "god", "goes", "going", "gone",
	"good", "got", "government", "grace", "grade", "grades", "graduate", "grant", "granted", "grants",
	"graph", "graphic", "gray", "great", "greater", "greatly", "green", "grid", "ground", "group",
	"groups", "grow", "growth", "guarantee", "guard", "guest", "guidance", "guide", "guidelines",
	"half", "hand", "handle", "handled", "handler", "handles", "handling", "hands", "handbook", "happen",
	"happened", "happens", "happy", "hard", "has", "hash", "have", "having", "he", "head", "header",
	"headline", "health", "hear", "heard", "hearing", "heart", "heavy", "held", "hello", "help",
	"helped", "helper", "helpful", "helping", "helps", "her", "here", "hero", "herself", "hi",
	"high", "higher", "highlight", "highlighted", "highly", "highschool", "him", "himself", "his",
	"history", "hit", "hold", "holding", "holds", "holiday", "home", "hope", "hoped", "hopes",
	"hoping", "hospitality", "host", "hosted", "hosting", "hour", "hours", "house", "houses", "how",
	"however", "huge", "human", "humanity", "hundred", "hypothesis", "i", "icon", "icons", "id",
	"idea", "ideal", "ideas", "identifier", "identifiers", "identify", "identity", "if", "ignore",
	"ignored", "ignoring", "image", "images", "immediate", "immediately", "impact", "implement",
	"implementation", "implemented", "implementing", "imply", "import", "importance", "important",
	"imported", "importing", "impressive", "improve", "improved", "improvement", "improvements",
	"in", "inbound", "inc", "include", "included", "includes", "including", "income", "incoming",
	"increase", "increased", "increment", "incremental", "indeed", "index", "indicate", "indicated",
	"indicates", "indication", "indicator", "individual", "individuals", "industry", "info", "information",
	"infrastrucutre", "initial", "initialize", "initialized", "initially", "input", "inputs", "inquiries",
	"inquiry", "insert", "inserted", "insertion", "inspect", "inspected", "inspecting", "inspection",
	"instance", "instances", "instant", "instantly", "instead", "instruction", "instructions", "intact",
	"integer", "integrate", "integrated", "integration", "integrity", "intend", "intended", "intent",
	"interaction", "interest", "interested", "interface", "interfered", "interfering", "intermediate",
	"internal", "international", "internet", "interpret", "interval", "interview", "into", "introduce",
	"invalid", "inventory", "investigate", "investigated", "investigation", "involve", "involved",
	"involvement", "issue", "issued", "issues", "it", "item", "items", "its", "itself", "january",
	"job", "jobs", "john", "join", "joined", "journal", "july", "june", "just", "keep", "keeping",
	"keeps", "kept", "key", "keys", "keyword", "kind", "kinds", "knew", "know", "knowing", "knowledge",
	"known", "knows", "label", "labels", "lack", "language", "large", "larger", "last", "late",
	"later", "latest", "launch", "launched", "launching", "lead", "leader", "leaders", "leadership",
	"leading", "learn", "learned", "learning", "least", "leave", "leaves", "leaving", "led", "left",
	"legible", "length", "less", "lesson", "lessons", "let", "lets", "letter", "letters", "level",
	"levels", "liable", "library", "license", "life", "lifetime", "light", "like", "liked", "likely",
	"likes", "limit", "limited", "limits", "line", "lines", "link", "linked", "linking", "links",
	"list", "listed", "listen", "listing", "lists", "literal", "little", "live", "lived", "lively",
	"liver", "lives", "living", "load", "loaded", "loader", "loading", "local", "location", "locations",
	"lock", "locked", "log", "logged", "logging", "logic", "logical", "login", "logs", "long",
	"longer", "look", "looked", "looking", "looks", "loop", "loose", "lost", "lot", "lots", "love",
	"loved", "low", "lower", "loyalty", "lunch", "mac", "machine", "made", "mail", "mailing", "main",
	"maintain", "maintained", "maintenance", "major", "make", "makes", "making", "male", "manage",
	"managed", "management", "manager", "managers", "managing", "manual", "manually", "many", "map",
	"mapped", "mapping", "maps", "march", "margin", "mark", "marked", "market", "marketing", "marking",
	"marks", "match", "matched", "matches", "matching", "material", "materials", "math", "matter",
	"matters", "maximum", "may", "maybe", "me", "mean", "meaning", "means", "meant", "media", "medical",
	"medium", "meet", "meeting", "meetings", "meets", "member", "members", "membership", "memory",
	"mention", "mentioned", "menu", "menus", "merge", "merged", "merging", "message", "messages",
	"messaging", "met", "meta", "metadata", "method", "methods", "middle", "might", "mile", "mind",
	"minimal", "minimum", "ministry", "minus", "minute", "minutes", "missing", "mission", "mode",
	"model", "models", "modes", "moderate", "modification", "modified", "modify", "modifying", "module",
	"monday", "money", "month", "monthly", "months", "more", "morning", "most", "mostly", "motion",
	"move", "moved", "movement", "moves", "moving", "much", "multiline", "multiple", "must", "my",
	"myself", "name", "named", "names", "national", "native", "natural", "nature", "near", "nearby",
	"nearly", "necessary", "need", "needed", "needing", "needs", "negative", "neighborhood", "neighbor",
	"neither", "nerve", "net", "network", "never", "new", "newer", "newest", "news", "next", "nice",
	"night", "nine", "no", "nobody", "node", "nodes", "noise", "none", "nor", "normal", "normalization",
	"normalize", "normalized", "normalizer", "normally", "north", "not", "note", "noted", "notes",
	"nothing", "notice", "notification", "notifications", "notified", "notify", "november", "now",
	"number", "numbers", "numeric", "object", "objective", "objects", "obtain", "obtained", "obvious",
	"obviously", "occasion", "occupy", "occur", "occurred", "occurring", "october", "of", "off",
	"offer", "offered", "office", "official", "officially", "offline", "offset", "often", "old",
	"older", "on", "once", "one", "ones", "online", "only", "open", "opened", "opening", "opens",
	"operate", "operating", "operation", "operations", "operator", "opinion", "opportunity", "opposite",
	"option", "optional", "options", "or", "order", "ordered", "orders", "ordinary", "organization",
	"organizations", "organized", "orientation", "origin", "original", "originally", "other", "others",
	"otherwise", "our", "ourselves", "out", "outbound", "outbox", "outcome", "outcomes", "outline",
	"output", "outputs", "outside", "overall", "overnight", "override", "overridden", "overview",
	"own", "owned", "owner", "owners", "package", "packages", "page", "pages", "paid", "pair",
	"pane", "panel", "paper", "paragraph", "paragraphs", "param", "parameter", "parameters", "parent",
	"parents", "park", "part", "partially", "participant", "participants", "participate", "participated",
	"participation", "particular", "particularly", "parties", "partner", "partners", "party", "pass",
	"passage", "passed", "passes", "passing", "past", "pastoral", "path", "pathway", "patient",
	"pattern", "patterns", "pay", "payment", "payments", "pending", "people", "per", "percent",
	"percentage", "perfect", "perfectly", "perform", "performance", "performed", "performing", "period",
	"permission", "permissions", "persist", "persisted", "persistence", "persistent", "person", "personal",
	"personality", "personally", "personnel", "persons", "phase", "phone", "phones", "photo", "photos",
	"phrase", "pick", "picked", "picture", "piece", "pill", "pills", "pilot", "pin", "place", "placed",
	"placeholder", "placement", "places", "plan", "planned", "planning", "plans", "platform", "play",
	"played", "player", "please", "pleased", "plenty", "plus", "pod", "point", "pointed", "pointer",
	"pointing", "points", "policy", "pool", "pop", "popup", "popups", "portion", "position", "positioned",
	"positions", "positive", "possibility", "possible", "possibly", "post", "posted", "posterior",
	"potential", "potentially", "power", "practical", "practice", "practices", "precede", "preceding",
	"precise", "precisely", "precision", "predict", "predictable", "preface", "prefer", "preference",
	"preferred", "prefix", "prep", "preparation", "prepare", "prepared", "presence", "present",
	"presentation", "presented", "presenting", "preserve", "preserved", "preserving", "press", "pressed",
	"pressing", "pressure", "prevent", "prevented", "preventing", "prevention", "preview", "previous",
	"previously", "price", "primary", "prime", "principal", "principle", "print", "printed", "prior",
	"priority", "privacy", "private", "privilege", "pro", "probability", "probable", "probably",
	"problem", "problems", "procedure", "proceed", "proceeded", "proceeding", "process", "processed",
	"processes", "processing", "processor", "produce", "produced", "produces", "product", "production",
	"products", "profile", "profiles", "program", "programmatic", "programming", "programs", "progress",
	"progressive", "project", "projects", "prominent", "promise", "promote", "promoted", "promotion",
	"prompt", "prompts", "proof", "proper", "properly", "properties", "property", "propose", "proposed",
	"protect", "protected", "protection", "protocol", "provide", "provided", "provider", "providers",
	"provides", "providing", "pub", "public", "publication", "publish", "published", "publisher",
	"publishing", "pull", "pulled", "pulling", "pulse", "purchase", "pure", "purple", "purpose",
	"push", "pushed", "pushing", "put", "puts", "putting", "qa", "qualification", "qualified",
	"quality", "quarter", "query", "querying", "question", "questionnaire", "questions", "queue",
	"queued", "queues", "quick", "quickly", "quiet", "quite", "quote", "race", "radio", "raise",
	"raised", "ram", "ran", "random", "range", "rank", "ranked", "ranking", "rapid", "rapidly",
	"rare", "rarely", "rate", "rated", "rates", "rather", "ratio", "raw", "re", "reach", "reached",
	"read", "readable", "reader", "reading", "readiness", "ready", "real", "realize", "realized",
	"really", "reason", "reasons", "rebuild", "receipt", "receipts", "receive", "received", "receiver",
	"receives", "receiving", "recent", "recently", "reception", "recipient", "recipients", "recognize",
	"recognized", "recommend", "recommendation", "recommended", "record", "recorded", "recording",
	"records", "recover", "recovered", "recovery", "red", "redesign", "reduce", "reduced", "ref",
	"reference", "referenced", "references", "referral", "referrals", "referred", "reflect", "reflected",
	"refactor", "refactored", "refactoring", "refresh", "refreshed", "refreshing", "refreshes",
	"regard", "regarding", "regardless", "region", "regional", "register", "registered", "registering",
	"registration", "registry", "regular", "regularly", "reject", "rejected", "rejection", "relate",
	"related", "relates", "relation", "relationship", "relationships", "relative", "relay", "relays",
	"release", "released", "relevant", "reliable", "relied", "relief", "rely", "remain", "remained",
	"remaining", "remains", "remark", "remember", "remembered", "remind", "reminder", "reminders",
	"remote", "remove", "removed", "removes", "removing", "render", "rendered", "rendering", "renders",
	"renew", "renewal", "repeat", "repeated", "replace", "replaced", "replacement", "replaces",
	"replacing", "replied", "replies", "reply", "replying", "report", "reported", "reporting",
	"reports", "represent", "represented", "representation", "request", "requested", "requesting",
	"requests", "require", "required", "requirement", "requirements", "requires", "research", "reset",
	"resident", "residents", "resolve", "resolved", "resolving", "resource", "resources", "respect",
	"respective", "respond", "responded", "responder", "responding", "response", "responses", "restaurant",
	"restaurants", "responsibility", "responsible", "rest", "restart", "restore", "restored", "result",
	"resulted", "resulting", "results", "retain", "retained", "retaining", "retention", "retry",
	"return", "returned", "returning", "returns", "reusable", "reuse", "reused", "reversing",
	"review", "reviewed", "reviewer", "reviewing", "reviews", "revision", "revisioning", "rich",
	"right", "rigid", "role", "roles", "roll", "rolled", "room", "rooms", "root", "rotational",
	"round", "rounded", "route", "router", "routes", "routine", "row", "rows", "rule", "rules",
	"run", "running", "runs", "runtime", "safe", "safely", "safety", "said", "same", "sample",
	"samples", "sandbox", "sarah", "sat", "saturday", "save", "saved", "saves", "saving", "saw",
	"say", "saying", "says", "scale", "scaled", "scan", "scanned", "scanner", "scanning", "schedule",
	"scheduled", "scheduler", "schedules", "scheduling", "schema", "school", "schools", "scope",
	"screen", "screens", "screenshot", "script", "scripts", "scroll", "scrolled", "scrolling",
	"seal", "seamless", "search", "searched", "searches", "searching", "season", "second", "seconds",
	"secret", "section", "sections", "secure", "securely", "security", "see", "seed", "seeded",
	"seeding", "seek", "seeking", "seem", "seemed", "seems", "seen", "sees", "select", "selected",
	"selecting", "selection", "selector", "selectors", "self", "send", "sender", "senders", "sending",
	"sends", "senior", "sense", "sensitive", "sent", "sentence", "sentinel", "separate", "separated",
	"separately", "separation", "september", "sequence", "sequential", "serial", "series", "serve",
	"served", "server", "servers", "service", "services", "serving", "session", "sessions", "set",
	"sets", "setting", "settings", "setup", "seven", "several", "shade", "shape", "shaped", "share",
	"shared", "shares", "sharing", "sheet", "sheets", "shell", "shift", "shifts", "shock", "short",
	"shortcut", "shortcuts", "shortly", "should", "show", "showed", "showing", "shown", "shows",
	"shrink", "side", "sidebar", "sideways", "sign", "signal", "signature", "signed", "significance",
	"significant", "significantly", "signing", "signup", "signups", "simple", "simplest", "simplicity",
	"simplified", "simplify", "simply", "simulate", "simulated", "simulating", "simulation", "since",
	"single", "site", "sites", "situation", "six", "size", "sizes", "sizing", "skill", "skills",
	"skip", "skipped", "skipping", "slide", "slides", "slight", "slightly", "slot", "slots", "slow",
	"slowly", "small", "smaller", "smart", "smile", "smooth", "smoothly", "so", "soft", "software",
	"solution", "solutions", "solve", "solved", "solving", "some", "somebody", "somehow", "someone",
	"something", "sometimes", "somewhere", "soon", "sorry", "sort", "sorted", "sorting", "sound",
	"source", "south", "space", "spaces", "spacious", "spans", "speak", "speaker", "speaking",
	"special", "specialist", "species", "specific", "specifically", "specification", "specified",
	"specify", "specifying", "specimen", "speech", "speed", "spell", "spelled", "spelling", "spells",
	"spend", "spent", "spin", "split", "spoken", "spot", "spread", "spring", "sql", "sqlite", "square",
	"stack", "staff", "staffing", "stage", "staging", "stand", "standard", "standards", "standing",
	"stands", "start", "started", "starting", "starts", "state", "statement", "statements", "states",
	"static", "station", "stationery", "stats", "statue", "status", "stay", "stayed", "staying",
	"stays", "stem", "stemming", "step", "steps", "stop", "stopped", "stopping", "stops", "storage",
	"store", "stored", "stores", "storing", "story", "straight", "strategy", "stream", "street",
	"strength", "strict", "strictly", "string", "strings", "strip", "stripped", "stripping", "strong",
	"strongly", "struct", "structure", "structured", "structures", "student", "students", "studio",
	"study", "studying", "stuff", "style", "styled", "styles", "sub", "subject", "subjects",
	"submit", "submitted", "submitting", "subset", "substantial", "subtle", "subtract", "subtraction",
	"succeed", "succeeded", "success", "successful", "successfully", "such", "suggest", "suggested",
	"suggesting", "suggestion", "suggestions", "suggests", "suit", "suite", "suites", "sum", "summarize",
	"summarized", "summary", "summer", "sun", "sunday", "supervisor", "supervisors", "supplement",
	"supplier", "support", "supported", "supporting", "supports", "suppress", "suppressed", "sure",
	"surely", "surface", "surge", "surprise", "surprised", "surprising", "system", "systems", "table",
	"tables", "tag", "tagged", "tags", "take", "taken", "takes", "taking", "talk", "talked", "talking",
	"talks", "target", "targeted", "targets", "task", "tasks", "team", "teams", "tech", "technical",
	"technology", "telephone", "template", "templates", "temporary", "ten", "tenant", "term",
	"terminal", "terms", "test", "tested", "testing", "tests", "text", "textbox", "textedit", "texts",
	"than", "thank", "thanks", "that", "thats", "the", "their", "them", "themselves", "then", "theme",
	"themes", "there", "thereby", "therefore", "these", "they", "thick", "thin", "thing", "things",
	"think", "thinking", "thinks", "third", "this", "thorough", "thoroughly", "those", "though",
	"thought", "thoughts", "thousand", "thread", "threaded", "threading", "threads", "three", "threshold",
	"through", "throughout", "throw", "thrown", "thursday", "thus", "ticket", "time", "timeframe",
	"timeout", "timer", "timers", "times", "timestamp", "timestamps", "timezone", "title", "titles",
	"today", "together", "token", "tokens", "told", "tolerance", "tomorrow", "too", "took", "tooltip",
	"tooltips", "top", "topic", "topics", "total", "totaled", "totally", "touch", "touched", "touching",
	"toward", "towards", "track", "tracked", "tracking", "tracks", "trade", "trained", "trainee",
	"trainer", "training", "transaction", "transactions", "transcript", "transfer", "transferred",
	"transform", "transformed", "transformation", "transition", "transitions", "translate", "translated",
	"translation", "transmit", "transmitted", "transmitting", "transparent", "transport", "treat",
	"treated", "tree", "trend", "trends", "trial", "trigger", "triggered", "triggering", "triggers",
	"trouble", "troubleshooting", "true", "truly", "trust", "trusted", "trustee", "try", "trying",
	"tuesday", "turn", "turned", "turning", "turns", "tutor", "tutors", "tutorial", "twenty", "twice",
	"twilio", "two", "type", "typed", "types", "typical", "typically", "typing", "ui", "unable",
	"unassigned", "uncovered", "under", "underlying", "understand", "understanding", "understood",
	"undo", "unexpected", "unhandled", "unified", "uniform", "union", "unique", "unit", "units",
	"universal", "university", "unknown", "unless", "unlinked", "unlike", "unlocked", "unnecessary",
	"unresolved", "unset", "unsupported", "until", "unusual", "update", "updated", "updates",
	"updating", "upgrade", "upgraded", "upgrading", "upon", "upper", "uppercase", "uri", "url",
	"urls", "us", "usage", "use", "used", "useful", "user", "username", "users", "uses", "using",
	"usual", "usually", "utility", "uuid", "uuid4", "uuids", "vacation", "val", "valid", "validate",
	"validated", "validating", "validation", "validity", "value", "values", "variable", "variables",
	"variance", "variant", "variants", "variation", "variety", "various", "vector", "vector2",
	"vendor", "vendors", "verbal", "verification", "verified", "verify", "verifying", "version",
	"versions", "vertical", "vertically", "very", "via", "vice", "vibrancy", "vibrant", "video",
	"view", "viewed", "viewer", "viewing", "viewports", "views", "violence", "visible", "visibility",
	"vision", "visit", "visited", "visiting", "visitor", "visitors", "visits", "visual", "visually",
	"voice", "voicemail", "voicemails", "volume", "volunteer", "volunteers", "vote", "voted", "waited",
	"waiting", "walk", "walkthrough", "wall", "wallet", "want", "wanted", "wanting", "wants", "warm",
	"warning", "warnings", "was", "wasn't", "water", "way", "ways", "we", "web", "website", "wednesday",
	"week", "weekend", "weekends", "weekly", "weeks", "welcome", "welcomed", "welcoming", "well",
	"went", "were", "what", "whatever", "whats", "when", "whenever", "where", "wherever", "whether",
	"which", "while", "white", "who", "whole", "whom", "whose", "why", "wide", "widely", "widget",
	"widgets", "width", "widths", "wife", "will", "willing", "win", "window", "windows", "wins",
	"wire", "wireframe", "wise", "wish", "wished", "wishes", "with", "within", "without", "woman",
	"women", "won", "won't", "wonder", "word", "words", "work", "worked", "worker", "workers",
	"workflow", "workflows", "working", "workplace", "works", "worksheet", "workspace", "world",
	"worry", "worth", "would", "wrap", "wrapped", "wrapping", "wraps", "write", "writer", "writes",
	"writing", "written", "wrong", "wrote", "year", "years", "yellow", "yes", "yesterday", "yet",
	"you", "your", "yours", "yourself", "youth", "zero", "zone"
]

const CONTRACTIONS = [
	"don't", "doesn't", "didn't", "won't", "wouldn't", "can't", "cannot", "couldn't", "shouldn't",
	"isn't", "aren't", "wasn't", "weren't", "hasn't", "haven't", "hadn't", "it's", "that's", "there's",
	"what's", "here's", "who's", "let's", "i'm", "you're", "he's", "she's", "we're", "they're",
	"i've", "you've", "we've", "they've", "i'll", "you'll", "he'll", "she'll", "we'll", "they'll",
	"i'd", "you'd", "he'd", "she'd", "we'd", "they'd"
]

static func _ensure_dictionary_loaded() -> void:
	if _is_dict_loaded:
		return
	_is_dict_loaded = true

	# 1. Seed Built-in Common English Vocabulary
	for w in COMMON_ENGLISH_WORDS:
		var lower = w.to_lower()
		_valid_word_set[lower] = true
		if not _candidate_word_list.has(lower):
			_candidate_word_list.append(lower)

	for c in CONTRACTIONS:
		_valid_word_set[c.to_lower()] = true

	# 2. Load System Dictionary Completely (/usr/share/dict/words) if available
	if FileAccess.file_exists("/usr/share/dict/words"):
		var f = FileAccess.open("/usr/share/dict/words", FileAccess.READ)
		if f:
			var line_idx = 0
			while not f.eof_reached():
				var raw_line = f.get_line().strip_edges()
				if raw_line.length() >= 2:
					var lower = raw_line.to_lower()
					_valid_word_set[lower] = true
					line_idx += 1
					if line_idx % 4 == 0 and _candidate_word_list.size() < 40000:
						if not _candidate_word_list.has(lower) and lower.is_valid_identifier():
							_candidate_word_list.append(lower)

static func is_word_valid(word: String) -> bool:
	_ensure_dictionary_loaded()

	var lower = word.to_lower()

	# Explicitly mapped typos are always flagged for suggestion mapping
	if SUGGESTION_MAP.has(lower):
		return false

	# 1. Direct valid set lookup
	if _valid_word_set.has(lower):
		return true

	# 2. Check user-ignored words in session
	if _ignored_words.has(lower):
		return true

	# 3. Ignore single letter words ('a', 'i')
	if lower.length() == 1:
		return true

	# 4. Ignore acronyms & upper-case codes (ALL CAPS >= 2 chars)
	if word == word.to_upper() and word.length() >= 2:
		return true

	# 5. Ignore tokens containing numbers or special chars (e.g. P-20260813, 123th, 555-0100, $50)
	var regex_digits = RegEx.new()
	regex_digits.compile("[0-9#\\$%\\&@\\/\\\\]")
	if regex_digits.search(word) != null:
		return true

	# 6. Possessive check (e.g. John's, constituent's, constituent' -> check base)
	if lower.ends_with("'s"):
		var base = lower.left(lower.length() - 2)
		if _valid_word_set.has(base) or is_word_valid(base):
			return true
	elif lower.ends_with("'"):
		var base = lower.left(lower.length() - 1)
		if _valid_word_set.has(base) or is_word_valid(base):
			return true

	# 7. Common English Inflection & Stemming checks
	if lower.ends_with("s") and lower.length() > 3:
		var stem1 = lower.left(lower.length() - 1)
		if _valid_word_set.has(stem1): return true

		if lower.ends_with("ies") and lower.length() > 4:
			var stem_y = lower.left(lower.length() - 3) + "y"
			if _valid_word_set.has(stem_y): return true

		if lower.ends_with("es") and lower.length() > 3:
			var stem_es = lower.left(lower.length() - 2)
			if _valid_word_set.has(stem_es): return true

	if lower.ends_with("ed") and lower.length() > 3:
		var stem1 = lower.left(lower.length() - 1)
		if _valid_word_set.has(stem1): return true
		var stem2 = lower.left(lower.length() - 2)
		if _valid_word_set.has(stem2): return true
		if lower.ends_with("ied") and lower.length() > 4:
			var stem_y = lower.left(lower.length() - 3) + "y"
			if _valid_word_set.has(stem_y): return true

	if lower.ends_with("ing") and lower.length() > 4:
		var stem1 = lower.left(lower.length() - 3)
		if _valid_word_set.has(stem1): return true
		var stem_e = lower.left(lower.length() - 3) + "e"
		if _valid_word_set.has(stem_e): return true

	if lower.ends_with("ly") and lower.length() > 3:
		var stem_ly = lower.left(lower.length() - 2)
		if _valid_word_set.has(stem_ly): return true

	return false

static func damerau_levenshtein(s1: String, s2: String) -> int:
	var len1 = s1.length()
	var len2 = s2.length()
	if len1 == 0: return len2
	if len2 == 0: return len1

	var d = []
	for i in range(len1 + 1):
		var row = []
		row.resize(len2 + 1)
		d.append(row)

	for i in range(len1 + 1):
		d[i][0] = i
	for j in range(len2 + 1):
		d[0][j] = j

	for i in range(1, len1 + 1):
		var char1 = s1[i - 1]
		for j in range(1, len2 + 1):
			var char2 = s2[j - 1]
			var cost = 0 if char1 == char2 else 1

			d[i][j] = min(d[i - 1][j] + 1, min(d[i][j - 1] + 1, d[i - 1][j - 1] + cost))

			if i > 1 and j > 1 and char1 == s2[j - 2] and s1[i - 2] == char2:
				d[i][j] = min(d[i][j], d[i - 2][j - 2] + cost)

	return d[len1][len2]

static func _letter_overlap(s1: String, s2: String) -> float:
	var counts1 = {}
	for c in s1: counts1[c] = counts1.get(c, 0) + 1
	var counts2 = {}
	for c in s2: counts2[c] = counts2.get(c, 0) + 1
	var shared = 0
	for c in counts1:
		if counts2.has(c):
			shared += min(counts1[c], counts2[c])
	return float(shared) / float(max(s1.length(), s2.length()))

static func find_suggestions(word: String) -> Array:
	_ensure_dictionary_loaded()
	var lower = word.to_lower()

	# 1. Direct explicit map match
	if SUGGESTION_MAP.has(lower):
		var explicit_sug = SUGGESTION_MAP[lower]
		if word.length() > 0 and word[0] == word[0].to_upper():
			explicit_sug = explicit_sug.capitalize()
		return [explicit_sug]

	# 2. Dynamic multi-criteria candidate ranking
	var scored_candidates = []
	var first_char = lower[0] if lower.length() > 0 else ""

	for dict_word in _candidate_word_list:
		if abs(dict_word.length() - lower.length()) > 3:
			continue

		var dist = damerau_levenshtein(lower, dict_word)
		var overlap = _letter_overlap(lower, dict_word)

		if dist <= 2 or (dist <= 4 and overlap > 0.65):
			var prefix_bonus = 4 if dict_word.begins_with(lower.left(3)) else (2 if dict_word.begins_with(first_char) else 0)
			var common_bonus = 3 if dict_word in COMMON_ENGLISH_WORDS else 0
			var score = dist * 10 - int(overlap * 15.0) - prefix_bonus - common_bonus

			scored_candidates.append({
				"word": dict_word,
				"score": score,
				"dist": dist,
				"len_diff": abs(dict_word.length() - lower.length())
			})

	scored_candidates.sort_custom(func(a, b):
		if a["score"] != b["score"]:
			return a["score"] < b["score"]
		return a["len_diff"] < b["len_diff"]
	)

	var suggestions = []
	for item in scored_candidates:
		var sug = item["word"]
		if word.length() > 0 and word[0] == word[0].to_upper():
			sug = sug.capitalize()
		if not suggestions.has(sug):
			suggestions.append(sug)
		if suggestions.size() >= 3:
			break

	return suggestions

static func check_text(text: String) -> Array:
	_ensure_dictionary_loaded()

	var issues = []
	if text.strip_edges() == "":
		return issues

	var regex = RegEx.new()
	regex.compile("\\b[a-zA-Z']+\\b")

	var matches = regex.search_all(text)
	for m in matches:
		var word = m.get_string()
		var lower = word.to_lower()

		if _ignored_words.has(lower):
			continue

		if is_word_valid(word):
			continue

		var sugs = find_suggestions(word)
		issues.append({
			"word": word,
			"suggestions": sugs,
			"start": m.get_start(),
			"end": m.get_end()
		})

	return issues

static func ignore_word(word: String) -> void:
	_ignored_words[word.to_lower()] = true

static func add_word_to_dictionary(word: String) -> void:
	_ensure_dictionary_loaded()
	var lower = word.to_lower()
	_valid_word_set[lower] = true
	if not _candidate_word_list.has(lower):
		_candidate_word_list.append(lower)

# --- Godot 4 Shared Inline Spell Checker Implementation ---

class InlineSpellingOverlay extends Control:
	var text_edit: TextEdit = null

	func _init(te: TextEdit):
		text_edit = te
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		z_index = 10
		anchor_left = 0.0
		anchor_top = 0.0
		anchor_right = 1.0
		anchor_bottom = 1.0
		offset_left = 0.0
		offset_top = 0.0
		offset_right = 0.0
		offset_bottom = 0.0

	func _notification(what: int) -> void:
		if what == NOTIFICATION_ENTER_TREE or what == NOTIFICATION_RESIZED or what == NOTIFICATION_VISIBILITY_CHANGED:
			if text_edit and is_instance_valid(text_edit):
				queue_redraw()

	func _draw() -> void:
		if not text_edit or not is_instance_valid(text_edit):
			return

		var total_lines = text_edit.get_line_count()
		var font = text_edit.get_theme_font("font")
		var font_size = text_edit.get_theme_font_size("font_size")
		var line_height = text_edit.get_line_height()

		var sb = text_edit.get_theme_stylebox("normal")
		var pad_left = sb.get_margin(SIDE_LEFT) if sb else 4.0
		var pad_top = sb.get_margin(SIDE_TOP) if sb else 4.0

		var scroll_v = text_edit.scroll_vertical if "scroll_vertical" in text_edit else 0
		var scroll_h = text_edit.scroll_horizontal if "scroll_horizontal" in text_edit else 0

		for line_idx in range(total_lines):
			var line_str = text_edit.get_line(line_idx)
			if line_str.strip_edges() == "":
				continue

			var issues = SpellingAssistanceHelper.check_text(line_str)
			if issues.size() == 0:
				continue

			var line_top_y = pad_top + (line_idx * line_height) - (scroll_v * line_height)
			var line_baseline_y = line_top_y + line_height - 3.0

			for iss in issues:
				var start_col = int(iss["start"])
				var end_col = int(iss["end"])

				var x_start = pad_left - scroll_h
				var x_end = pad_left - scroll_h

				if font:
					x_start += font.get_string_size(line_str.left(start_col), HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
					x_end += font.get_string_size(line_str.left(end_col), HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x

				# Fallback if get_pos_at_line_column returns valid non-negative coordinates
				var p1 = text_edit.get_pos_at_line_column(line_idx, start_col)
				var p2 = text_edit.get_pos_at_line_column(line_idx, end_col)
				if p1.x >= 0 and p1.y >= 0 and p2.x >= 0:
					x_start = p1.x
					x_end = p2.x
					line_baseline_y = p1.y + line_height - 3.0

				if x_start >= 0 and x_end > x_start:
					_draw_word_wave(x_start, x_end, line_baseline_y)

	func _draw_word_wave(x_start: float, x_end: float, y_baseline: float) -> void:
		var wave_pts = PackedVector2Array()
		var x = x_start
		var wave_up = true
		while x <= x_end:
			var y_off = -1.5 if wave_up else 1.5
			wave_pts.append(Vector2(x, y_baseline + y_off))
			x += 2.5
			wave_up = not wave_up

		if wave_pts.size() >= 2:
			draw_polyline(wave_pts, Color(0.95, 0.20, 0.20, 0.95), 1.5, true)

static func attach_inline_spell_check(text_edit: TextEdit) -> void:
	if not text_edit or not is_instance_valid(text_edit):
		return

	for child in text_edit.get_children():
		if child is InlineSpellingOverlay:
			return

	# Rule Compliance: App-Wide Blinking Cursor / Caret Rule
	text_edit.caret_blink = true
	text_edit.add_theme_color_override("caret_color", Color(0.12, 0.16, 0.22, 1.0))
	text_edit.context_menu_enabled = true

	# Attach Overlay Drawer for Red Squiggly Underline
	var overlay = InlineSpellingOverlay.new(text_edit)
	text_edit.add_child(overlay)
	overlay.z_index = 10

	var redraw_cb = func():
		if is_instance_valid(overlay):
			overlay.queue_redraw()

	text_edit.text_changed.connect(redraw_cb)
	if text_edit.has_signal("scroll_vertical_changed"):
		text_edit.scroll_vertical_changed.connect(redraw_cb)
	if text_edit.has_signal("scroll_horizontal_changed"):
		text_edit.scroll_horizontal_changed.connect(redraw_cb)
	text_edit.resized.connect(redraw_cb)
	text_edit.focus_entered.connect(redraw_cb)

	# Right-Click / Control-Click Context Menu Correction
	text_edit.gui_input.connect(func(event: InputEvent):
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
			var click_pos = event.position
			var font = text_edit.get_theme_font("font")
			var font_size = text_edit.get_theme_font_size("font_size")
			var line_height = text_edit.get_line_height()

			var sb = text_edit.get_theme_stylebox("normal")
			var pad_left = sb.get_margin(SIDE_LEFT) if sb else 4.0
			var pad_top = sb.get_margin(SIDE_TOP) if sb else 4.0
			var scroll_v = text_edit.scroll_vertical if "scroll_vertical" in text_edit else 0
			var scroll_h = text_edit.scroll_horizontal if "scroll_horizontal" in text_edit else 0

			var line_col = text_edit.get_line_column_at_pos(click_pos)
			var target_line = line_col.y
			var target_col = line_col.x

			if target_line < 0 or target_line >= text_edit.get_line_count():
				target_line = int(clamp(floor((click_pos.y - pad_top + scroll_v) / line_height), 0, text_edit.get_line_count() - 1))

			var line_str = text_edit.get_line(target_line)
			if target_col < 0 or target_col > line_str.length():
				var cur_x = pad_left - scroll_h
				target_col = 0
				for c in range(line_str.length()):
					var char_w = font.get_string_size(line_str.substr(c, 1), HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
					if click_pos.x < cur_x + (char_w / 2.0):
						break
					cur_x += char_w
					target_col = c + 1

			var issues = check_text(line_str)
			var matched_issue = null

			for iss in issues:
				if target_col >= int(iss["start"]) and target_col <= int(iss["end"]):
					matched_issue = iss
					break

			if matched_issue != null:
				text_edit.accept_event()

				var target_word = str(matched_issue["word"])
				var sugs: Array = matched_issue["suggestions"]

				var popup = PopupMenu.new()
				text_edit.add_child(popup)

				var item_idx = 0
				if sugs.size() > 0:
					for sug in sugs:
						popup.add_item("✨ Replace with \"" + str(sug) + "\"", item_idx)
						popup.set_item_metadata(item_idx, { "action": "replace", "val": str(sug) })
						item_idx += 1
				else:
					popup.add_item("(No confident suggestion)", item_idx)
					popup.set_item_disabled(item_idx, true)
					item_idx += 1

				popup.add_separator()
				item_idx += 1

				popup.add_item("🙈 Ignore \"" + target_word + "\"", item_idx)
				popup.set_item_metadata(item_idx, { "action": "ignore", "val": target_word })
				item_idx += 1

				popup.add_item("➕ Add \"" + target_word + "\" to Dictionary", item_idx)
				popup.set_item_metadata(item_idx, { "action": "add_dict", "val": target_word })
				item_idx += 1

				popup.add_separator()
				item_idx += 1

				popup.add_item("✂️ Cut", item_idx)
				popup.set_item_metadata(item_idx, { "action": "edit_cut" })
				item_idx += 1

				popup.add_item("📋 Copy", item_idx)
				popup.set_item_metadata(item_idx, { "action": "edit_copy" })
				item_idx += 1

				popup.add_item("📥 Paste", item_idx)
				popup.set_item_metadata(item_idx, { "action": "edit_paste" })
				item_idx += 1

				popup.id_pressed.connect(func(id: int):
					var idx = popup.get_item_index(id)
					var meta = popup.get_item_metadata(idx)
					if meta != null and meta is Dictionary:
						var act = meta.get("action", "")
						if act == "replace":
							var sug_val = str(meta.get("val", ""))
							var full_txt = text_edit.text
							var issue_start = int(matched_issue["start"])
							var issue_end = int(matched_issue["end"])

							var global_start = 0
							for i in range(target_line):
								global_start += text_edit.get_line(i).length() + 1
							global_start += issue_start
							var global_end = global_start + (issue_end - issue_start)

							text_edit.text = full_txt.left(global_start) + sug_val + full_txt.substr(global_end)
							text_edit.text_changed.emit()
							redraw_cb.call()

						elif act == "ignore":
							ignore_word(target_word)
							text_edit.text_changed.emit()
							redraw_cb.call()

						elif act == "add_dict":
							add_word_to_dictionary(target_word)
							text_edit.text_changed.emit()
							redraw_cb.call()

						elif act == "edit_cut":
							text_edit.cut()
						elif act == "edit_copy":
							text_edit.copy()
						elif act == "edit_paste":
							text_edit.paste()

					popup.queue_free()
				)

				var global_mouse_pos = text_edit.get_global_mouse_position()
				popup.position = Vector2i(int(global_mouse_pos.x), int(global_mouse_pos.y))
				popup.reset_size()
				popup.popup()
	)

# Backwards Compatibility Helper Method (Ensures no legacy warning bar is ever created)
func attach_to_text_edit(text_edit: TextEdit, _parent_container: Container = null) -> Control:
	attach_inline_spell_check(text_edit)
	return null
