# 技能图鉴:44 个技能(正位+逆位)的用法演示,复盘式每一步标注
# 棋盘为标准中国象棋开局布局(黑上红下)
extends Control

const Perks := preload("res://scripts/perks.gd")
const Tarot := preload("res://scripts/tarot.gd")
const TarotTooltip := preload("res://scripts/tarot_tooltip.gd")
const TarotCard := preload("res://scripts/perk_card.gd")

const BOARD_STANDARD := [
	"RHEAKAEHR",
	".........",
	".C.....C.",
	"P.P.P.P.P",
	".........",
	".........",
	"p.p.p.p.p",
	".c.....c.",
	".........",
	"rheakaehr",
]

# 演示数据:skill_id -> { steps: [{board, text}] }
const DEMOS := {
	"yuzhe": {
		"steps": [
			{
				"board": [
					"RHEAKAEHR",
					".........",
					".C.....C.",
					"P.P.P.P.P",
					".........",
					".........",
					"p.p.p.p.p",
					".c.....c.",
					".........",
					"rheakaehr",
				],
				"text": "愚者(正位) · 主动 · 8回合\n用法:打乱全场棋子位置,每子 75% 概率不动,帅将士不动。\n策略:破阵——打乱对方布局,但自己阵型也受影响。使用后跳过本回合。",
			},
			{
				"board": [
					"RHEAKAEHR",
					".........",
					".C.....C.",
					"P.P.h.P.P",
					".........",
					".........",
					"p.p.p.p.p",
					".c..h..c.",
					".........",
					"r.eakaePr",
				],
				"text": "使用后:棋子位置被打乱(这里演示部分打乱效果),帅(将)与士保持原位。\n适合:对方阵型紧凑时强行拆散;慎用:己方阵型也会乱。",
			},
		],
	},
	"moshushi": {
		"steps": [
			{
				"board": [
					"RHEAKAEHR",
					".........",
					".C.....C.",
					"P.P.P.P.P",
					".........",
					".........",
					"p.p.p.p.p",
					".c.....c.",
					".........",
					"rheakaehr",
				],
				"text": "魔术师(正位) · 主动 · 6回合\n用法:交换我方两枚棋子的位置。\n策略:把强子调到有利位置,或救出被围棋子。使用后消耗本回合。",
			},
			{
				"board": [
					"RHEAKAEHR",
					".........",
					".C.....C.",
					"P.P.P.P.P",
					".........",
					".........",
					"p.p.p.p.p",
					".h.....c.",
					".........",
					"rceakaehr",
				],
				"text": "使用后:我方两枚棋子位置交换(演示:红马与红炮互换)。\n操作:点击第一枚己方棋子,再点击第二枚。",
			},
		],
	},
	"nvjisi": {
		"steps": [
			{
				"board": [
					"RHEAKAEHR",
					".........",
					".C.....C.",
					"P.P.P.P.P",
					".........",
					".........",
					"p.p.p.p.p",
					".c.....c.",
					".........",
					"rheakaehr",
				],
				"text": "女祭司(正位) · 主动 · 3回合\n用法:所有兵前进一格,并补全己方所有兵。\n策略:集体推进兵线,同时补满兵力。",
			},
			{
				"board": [
					"RHEAKAEHR",
					".........",
					".C.....C.",
					"P.P.P.P.P",
					".........",
					".........",
					"p.ppp.p.p",
					".c.....c.",
					".........",
					"rheakaehr",
				],
				"text": "使用后:所有兵前进一格(演示:红兵集体前移),兵线空位补满。",
			},
		],
	},
	"huanghou": {
		"steps": [
			{
				"board": [
					"RHEAKAEHR",
					".........",
					".C.....C.",
					"P.P.P.P.P",
					".........",
					".........",
					"p.p.p.p.p",
					".c.....c.",
					".........",
					"rheakaehr",
				],
				"text": "皇后(正位) · 主动 · 被吃充能3\n用法:己方每被吃 1 子充能 1 点(上限3),消耗 1 点后所有棋子获得无敌。\n策略:被吃子攒充能,关键时刻全体免死。",
			},
			{
				"board": [
					"RHEAKAEHR",
					".........",
					".C.....C.",
					"P.P.P.P.P",
					".........",
					".........",
					"p.p.p.p.p",
					".c.....c.",
					".........",
					"rheakaehr",
				],
				"text": "使用后:红方所有棋子本回合无敌(演示:红车被选中也无法被吃)。",
			},
		],
	},
	"huangdi": {
		"steps": [
			{
				"board": [
					"RHEAKAEHR",
					".........",
					".C.....C.",
					"P.P.P.P.P",
					".........",
					".........",
					"p.p.p.p.p",
					".c.....c.",
					".........",
					"rheakaehr",
				],
				"text": "皇帝(正位) · 主动 · 3回合\n用法:指定己方一子本回合无敌。\n策略:保护关键棋子(车/帅)不被吃。",
			},
			{
				"board": [
					"RHEAKAEHR",
					".........",
					".C.....C.",
					"P.P.P.P.P",
					".........",
					".........",
					"p.p.p.p.p",
					".c.....c.",
					".........",
					"rheakaehr",
				],
				"text": "使用后:被指定的棋子本回合不可被吃(演示:红车获得无敌标记)。",
			},
		],
	},
	"jiaohuang": {
		"steps": [
			{
				"board": [
					"RHEAKAEHR",
					".........",
					".C.....C.",
					"P.P.P.P.P",
					".........",
					".........",
					"p.p.p.p.p",
					".c.....c.",
					".........",
					"rheakaehr",
				],
				"text": "教皇(正位) · 被动 · 象强化\n用法:以象为中心 5×5 范围内(除象自身)的己方棋子获得无敌。\n策略:让象护住兵线,周边棋子可放心吃子。",
			},
			{
				"board": [
					"RHEAKAEHR",
					".........",
					".C.....C.",
					"P.P.P.P.P",
					".........",
					".........",
					"p.p.p.p.p",
					".c.....c.",
					".........",
					"rheakaehr",
				],
				"text": "效果:象 5×5 范围内(除象自身)的己方棋子获得无敌。",
			},
		],
	},
	"lianren": {
		"steps": [
			{
				"board": [
					"RHEAKAEHR",
					".........",
					".C.....C.",
					"P.P.P.P.P",
					".........",
					".........",
					"p.p.p.p.p",
					".c.....c.",
					".........",
					"rheakaehr",
				],
				"text": "恋人(正位) · 被动\n用法:己方每被吃 2 子,复活 1 子到同类棋子出生位置(位置被占则不可复活)。\n策略:鼓励主动兑子,靠复活维持兵力。",
			},
			{
				"board": [
					"RHEAKAEHR",
					".........",
					".C.....C.",
					"P.P.P.P.P",
					".........",
					".........",
					"p.p.ppp.p",
					".c.....c.",
					".........",
					"rheakaehr",
				],
				"text": "效果:被吃的第 2/4/6... 个棋子会复活(演示:红兵复活回兵线)。",
			},
		],
	},
	"zhanche": {
		"steps": [
			{
				"board": [
					"RHEAKAEHR",
					".........",
					".C.....C.",
					"P.P.P.P.P",
					".........",
					".........",
					"p.p.p.p.p",
					".c.....c.",
					".........",
					"rheakaehr",
				],
				"text": "战车(正位) · 主动 · 3回合\n用法:指定车相邻的一枚己方棋子,将该子移至车的可落位。\n策略:用车的机动性给相邻子开出一条路。",
			},
			{
				"board": [
					"RHEAKAEHR",
					".........",
					".C.....C.",
					"P.P.P.P.P",
					".........",
					".........",
					"p.p.p.p.p",
					".c.....c.",
					".........",
					"r.ehkaehr",
				],
				"text": "使用后:车相邻的棋子被移到车的可落位(演示:红马移到车可到达的位置)。",
			},
		],
	},
	"zhengyi": {
		"steps": [
			{
				"board": [
					"RHEAKAEHR",
					".........",
					".C.....C.",
					"P.P.P.P.P",
					".........",
					".........",
					"p.p.p.p.p",
					".c.....c.",
					".........",
					"rheakaehr",
				],
				"text": "正义(正位) · 被动 · 马强化\n用法:马不会被别马腿,可跳过阻挡;还能落到另一匹马所能落位的位置。\n策略:马变成真正的野马,机动性大增。",
			},
			{
				"board": [
					"RHEAKAEHR",
					".........",
					".C.....C.",
					"P.P.P.P.P",
					".........",
					".........",
					"p.p.p.p.p",
					".c.....c.",
					".........",
					"rheakaehr",
				],
				"text": "效果:马无视阻挡(演示:红马跳过挡路的棋子)。",
			},
		],
	},
	"yinzhe": {
		"steps": [
			{
				"board": [
					"RHEAKAEHR",
					".........",
					".C.....C.",
					"P.P.P.P.P",
					".........",
					".........",
					"p.p.p.p.p",
					".c.....c.",
					".........",
					"rheakaehr",
				],
				"text": "隐者(正位) · 主动 · 3回合\n用法:指定己方两枚棋子隐身两回合,隐身的子不能吃子。\n策略:让关键子隐身潜行,但隐身时不能攻击。",
			},
			{
				"board": [
					"RHEAKAEHR",
					".........",
					".C.....C.",
					"P.P.P.P.P",
					".........",
					".........",
					"p.p.p.p.p",
					".c.....c.",
					".........",
					"rheakaehr",
				],
				"text": "使用后:选中的两枚棋子隐身两回合(对方看不到,也无法被吃)。",
			},
		],
	},
	"mingyun": {
		"steps": [
			{
				"board": [
					"RHEAKAEHR",
					".........",
					".C.....C.",
					"P.P.P.P.P",
					".........",
					".........",
					"p.p.p.p.p",
					".c.....c.",
					".........",
					"rheakaehr",
				],
				"text": "命运之轮(正位) · 主动 · 4回合\n用法:该回合可额外移动一次(不能连续动同一子)。释放不消耗本回合。\n策略:多一次行动,加快进攻节奏。",
			},
			{
				"board": [
					"RHEAKAEHR",
					".........",
					".C.....C.",
					"P.P.P.P.P",
					".........",
					".........",
					"p.p.p.p.p",
					".c.....c.",
					".........",
					"rheakaehr",
				],
				"text": "使用后:本回合可额外移动一次(演示:红车走两步)。",
			},
		],
	},
	"liliang": {
		"steps": [
			{
				"board": [
					"RHEAKAEHR",
					".........",
					".C.....C.",
					"P.P.P.P.P",
					".........",
					".........",
					"p.p.p.p.p",
					".c.....c.",
					".........",
					"rheakaehr",
				],
				"text": "力量(正位) · 被动\n用法:主动技能充能上限-1(冷却减少1回合)。\n策略:让所有主动技能更快冷却。",
			},
			{
				"board": [
					"RHEAKAEHR",
					".........",
					".C.....C.",
					"P.P.P.P.P",
					".........",
					".........",
					"p.p.p.p.p",
					".c.....c.",
					".........",
					"rheakaehr",
				],
				"text": "效果:己方主动技能冷却 -1。",
			},
		],
	},
	"diaodiao": {
		"steps": [
			{
				"board": [
					"RHEAKAEHR",
					".........",
					".C.....C.",
					"P.P.P.P.P",
					".........",
					".........",
					"p.p.p.p.p",
					".c.....c.",
					".........",
					"rheakaehr",
				],
				"text": "倒吊人(正位) · 主动 · 2回合\n用法:使用后跳过本回合,在操控己方棋子和非己方棋子间切换。默认操控己方,使用后变为只能操控非己方棋子(可吃子),再次使用切回己方。\n策略:操控对方棋子打乱阵型,或用对方子吃子。",
			},
			{
				"board": [
					"RHEAKAEHR",
					".........",
					".C.....C.",
					"P.P.P.P.P",
					".........",
					".........",
					"p.p.p.p.p",
					".c.....c.",
					".........",
					"rheakaehr",
				],
				"text": "使用后:切换为操控非己方棋子(演示:黑車可被红方操控移动,且可吃子)。再次使用切回操控己方。",
			},
		],
	},
	"siwang": {
		"steps": [
			{
				"board": [
					"RHEAKAEHR",
					".........",
					".C.....C.",
					"P.P.P.P.P",
					".........",
					".........",
					"p.p.p.p.p",
					".c.....c.",
					".........",
					"rheakaehr",
				],
				"text": "死亡(正位) · 主动 · 被吃充能2\n用法:己方每被吃 1 子充能 1 点,消耗 1 点后指定己方一子,摧毁敌我各一枚同类型子。\n策略:同归于尽式兑子,专克对方强子。",
			},
			{
				"board": [
					"R.EAKAEHR",
					".........",
					".C.....C.",
					"P.P.P.P.P",
					".........",
					".........",
					"p.p.p.p.p",
					".c.....c.",
					".........",
					"r.eakaehr",
				],
				"text": "使用后:敌我各一枚同类型子被摧毁(演示:红马与黑馬同时消失)。",
			},
		],
	},
	"jiezhi": {
		"steps": [
			{
				"board": [
					"RHEAKAEHR",
					".........",
					".C.....C.",
					"P.P.P.P.P",
					".........",
					".........",
					"p.p.p.p.p",
					".c.....c.",
					".........",
					"rheakaehr",
				],
				"text": "节制(正位) · 主动\n用法:跳过该回合,下回合己方追加一额外回合。\n策略:调整节奏——这回合不动,下回合连动。",
			},
			{
				"board": [
					"RHEAKAEHR",
					".........",
					".C.....C.",
					"P.P.P.P.P",
					".........",
					".........",
					"p.p.p.p.p",
					".c.....c.",
					".........",
					"rheakaehr",
				],
				"text": "使用后:跳过本回合,下回合追加一次行动。",
			},
		],
	},
	"emo": {
		"steps": [
			{
				"board": [
					"RHEAKAEHR",
					".........",
					".C.....C.",
					"P.P.P.P.P",
					".........",
					".........",
					"p.p.p.p.p",
					".c.....c.",
					".........",
					"rheakaehr",
				],
				"text": "恶魔(正位) · 被动\n用法:敌方无法使用同类型的子连续吃掉我方棋子。\n策略:让对方同一兵种无法连续收割,限制对方连杀。",
			},
			{
				"board": [
					"RHEAKAEHR",
					".........",
					".C.....C.",
					"P.P.P.P.P",
					".........",
					".........",
					"p.p.p.p.p",
					".c.....c.",
					".........",
					"rheakaehr",
				],
				"text": "效果:对方用车吃了我方一子后,同回合不能再用车吃第二个。",
			},
		],
	},
	"ta": {
		"steps": [
			{
				"board": [
					"RHEAKAEHR",
					".........",
					".C.....C.",
					"P.P.P.P.P",
					".........",
					".........",
					"p.p.p.p.p",
					".c.....c.",
					".........",
					"rheakaehr",
				],
				"text": "塔(正位) · 被动 · 开局生效\n用法:开局额外获得四枚兵;兵过河后可斜向前吃子。\n策略:开局兵力优势,过河兵更凶。",
			},
			{
				"board": [
					"RHEAKAEHR",
					".........",
					".C.....C.",
					"P.P.P.P.P",
					".........",
					".........",
					"p.p.p.p.p",
					".c.....c.",
					"p.p.p.p..",
					"rheakaehr",
				],
				"text": "效果:开局多 4 枚兵(演示:红方共 9 枚兵)。",
			},
		],
	},
	"xingxing": {
		"steps": [
			{
				"board": [
					"RHEAKAEHR",
					".........",
					".C.....C.",
					"P.P.P.P.P",
					".........",
					".........",
					"p.p.p.p.p",
					".c.....c.",
					".........",
					"rheakaehr",
				],
				"text": "星星(正位) · 被动 · 每回合一次\n用法:每回合一次,兵/卒可无代价向后移动一格(不消耗行动)。\n策略:兵后退保命,或调整兵线。",
			},
			{
				"board": [
					"RHEAKAEHR",
					".........",
					".C.....C.",
					"P.P.P.P.P",
					".........",
					".........",
					"p.p.p.p.p",
					".c.....c.",
					".........",
					"rheakaehr",
				],
				"text": "效果:兵可免费后退一格(演示:红兵蓝色退兵位)。",
			},
		],
	},
	"yueliang": {
		"steps": [
			{
				"board": [
					"RHEAKAEHR",
					".........",
					".C.....C.",
					"P.P.P.P.P",
					".........",
					".........",
					"p.p.p.p.p",
					".c.....c.",
					".........",
					"rheakaehr",
				],
				"text": "月亮(正位) · 被动 · 象强化\n用法:象的移动距离不受限制(沿斜线任意距离,路径需为空,可吃路径上第一个子)。\n策略:象变成远程斜线重炮。",
			},
			{
				"board": [
					"RHEAKAEHR",
					".........",
					".C.....C.",
					"P.P.P.P.P",
					".........",
					".........",
					"p.p.p.p.p",
					".c..e..c.",
					".........",
					"rh.akaehr",
				],
				"text": "效果:象可沿斜线走任意距离(演示:红相走到中场)。",
			},
		],
	},
	"taiyang": {
		"steps": [
			{
				"board": [
					"RHEAKAEHR",
					".........",
					".C.....C.",
					"P.P.P.P.P",
					".........",
					".........",
					"p.p.p.p.p",
					".c.....c.",
					".........",
					"rheakaehr",
				],
				"text": "太阳(正位) · 被动 · 车强化\n用法:车可以斜走一格。\n策略:车多 4 个斜向出口,摆脱直线束缚。",
			},
			{
				"board": [
					"RHEAKAEHR",
					".........",
					".C.....C.",
					"P.P.P.P.P",
					".........",
					".........",
					"p.p.p.p.p",
					".c.....c.",
					".........",
					"rheakaehr",
				],
				"text": "效果:车可斜走一格(演示:红车可走对角一格)。",
			},
		],
	},
	"shenpan": {
		"steps": [
			{
				"board": [
					"RHEAKAEHR",
					".........",
					".C.....C.",
					"P.P.P.P.P",
					".........",
					".........",
					"p.p.p.p.p",
					".c.....c.",
					".........",
					"rheakaehr",
				],
				"text": "审判(正位) · 被动\n用法:每回合随机禁用敌方一个主动技能。\n策略:让对方关键主动技能哑火。",
			},
			{
				"board": [
					"RHEAKAEHR",
					".........",
					".C.....C.",
					"P.P.P.P.P",
					".........",
					".........",
					"p.p.p.p.p",
					".c.....c.",
					".........",
					"rheakaehr",
				],
				"text": "效果:每回合敌方随机一个主动技能被禁用。",
			},
		],
	},
	"shijie": {
		"steps": [
			{
				"board": [
					"RHEAKAEHR",
					".........",
					".C.....C.",
					"P.P.P.P.P",
					".........",
					".........",
					"p.p.p.p.p",
					".c.....c.",
					".........",
					"rheakaehr",
				],
				"text": "世界(正位) · 被动\n用法:每回合每个己方棋子有 10% 概率变为任意棋子(将帅除外),弱子概率高、强子概率低。\n策略:低概率赌变子,可能变出强子。",
			},
			{
				"board": [
					"RHEAKAEHR",
					".........",
					".C.....C.",
					"P.P.P.P.P",
					".........",
					".........",
					"r.p.p.p.p",
					".c.....c.",
					".........",
					"rheakaehr",
				],
				"text": "效果:己方棋子随机变型(演示:红兵变为红车)。",
			},
		],
	},
	"yuzhe2": {
		"steps": [
			{
				"board": [
					"RHEAKAEHR",
					".........",
					".C....C..",
					"P.P.P.P.P",
					".........",
					".h.....e.",
					"p.p.p.p.p",
					".c.....c.",
					".........",
					".heakaeh.",
				],
				"text": "愚者(逆位) · 主动 · 16回合(开局充能)\n用法:复原所有棋子位置(不复活被吃子)。\n策略:把混乱的棋局拉回开局布局,重置战场。",
			},
			{
				"board": [
					"RHEAKAEHR",
					".........",
					".C.....C.",
					"P.P.P.P.P",
					".........",
					".........",
					"p.p.p.p.p",
					".c.....c.",
					".........",
					"rheakaehr",
				],
				"text": "使用后:现存棋子全部回到开局位置(演示:混乱的棋盘复原为标准布局)。",
			},
		],
	},
	"moshushi2": {
		"steps": [
			{
				"board": [
					"RHEAKAEHR",
					".........",
					".C.....C.",
					"P.P.P.P.P",
					".........",
					".........",
					"p.p.p.p.p",
					".c.....c.",
					".........",
					"rheakaehr",
				],
				"text": "魔术师(逆位) · 主动 · 6回合\n用法:交换敌方两枚棋子的位置。\n策略:把对方棋子调到坏位置,拆散对方防线。",
			},
			{
				"board": [
					"RREAKAEHR",
					".........",
					".C.....C.",
					"P.P.P.P.P",
					".........",
					".........",
					"p.p.p.p.p",
					".c.....c.",
					".........",
					"rheakaehr",
				],
				"text": "使用后:敌方两子位置交换(演示:黑車与黑馬互换)。",
			},
		],
	},
	"nvjisi2": {
		"steps": [
			{
				"board": [
					"RHEAKAEHR",
					".........",
					".C.....C.",
					"P.P.P.P.P",
					".........",
					".........",
					"p.p.p.p.p",
					".c.....c.",
					".........",
					"rheakaehr",
				],
				"text": "女祭司(逆位) · 主动 · 7回合\n用法:在我方底线随机位置生成一个随机棋子(兵和士除外)。\n策略:底线补强,可能变出车/炮等强子。",
			},
			{
				"board": [
					"RHEAKAEHR",
					".........",
					".C.....C.",
					"P.P.P.P.P",
					".........",
					".........",
					"p.p.p.p.p",
					".c.....c.",
					".........",
					"rhearaehr",
				],
				"text": "使用后:底线生成一个随机棋子(演示:红底线多一枚车,不会生成兵/士)。",
			},
		],
	},
	"huanghou2": {
		"steps": [
			{
				"board": [
					"RHEAKAEHR",
					".........",
					".C.....C.",
					"P.P.P.P.P",
					".........",
					".........",
					"p.p.p.p.p",
					".c.....c.",
					".........",
					"rheakaehr",
				],
				"text": "皇后(逆位) · 主动 · 被吃充能3\n用法:消耗 1 点充能,所有棋子获得反制——被吃时与对方同归于尽。\n策略:威慑对方不敢吃你的子。",
			},
			{
				"board": [
					"RHEAKAEHR",
					".........",
					".C.....C.",
					"P.P.P.P.P",
					".........",
					".........",
					"p.p.p.p.p",
					".c.....c.",
					".........",
					"rheakaehr",
				],
				"text": "使用后:红方所有棋子反制(演示:对方吃红车时,攻击者也消失)。",
			},
		],
	},
	"huangdi2": {
		"steps": [
			{
				"board": [
					"RHEAKAEHR",
					".........",
					".C.....C.",
					"P.P.P.P.P",
					".........",
					".........",
					"p.p.p.p.p",
					".c.....c.",
					".........",
					"rheakaehr",
				],
				"text": "皇帝(逆位) · 主动 · 3回合\n用法:指定己方一子获得反制(被吃时同归于尽)。\n策略:给关键子挂反制,对方吃它就自杀。",
			},
			{
				"board": [
					"RHEAKAEHR",
					".........",
					".C.....C.",
					"P.P.P.P.P",
					".........",
					".........",
					"p.p.p.p.p",
					".c.....c.",
					".........",
					"rheakaehr",
				],
				"text": "使用后:指定棋子被吃时与对方同归于尽(演示:红车挂反制)。",
			},
		],
	},
	"jiaohuang2": {
		"steps": [
			{
				"board": [
					"RHEAKAEHR",
					".........",
					".C.....C.",
					"P.P.P.P.P",
					".........",
					".........",
					"p.p.p.p.p",
					".c.....c.",
					".........",
					"rheakaehr",
				],
				"text": "教皇(逆位) · 被动 · 象强化\n用法:以象为中心 5×5 范围内(除象自身)的所有棋子获得反制(被吃时同归于尽)。\n策略:象附近变成雷区,敌方不敢踏入。",
			},
			{
				"board": [
					"RHEAKAEHR",
					".........",
					".C.....C.",
					"P.P.P.P.P",
					".........",
					".........",
					"p.p.p.p.p",
					".c.....c.",
					".........",
					"rheakaehr",
				],
				"text": "效果:象 5×5 范围内(除象自身)的棋子被吃时攻击者也消失。",
			},
		],
	},
	"lianren2": {
		"steps": [
			{
				"board": [
					"RHEAKAEHR",
					".........",
					".C.....C.",
					"P.P.P.P.P",
					".........",
					".........",
					"p.p.p.p.p",
					".c.....c.",
					".........",
					"rheakaehr",
				],
				"text": "恋人(逆位) · 主动 · 被吃充能2\n用法:己方每被吃 1 子充能 1 点(需 2 点),使用后己方其他技能全部完成冷却/充能。\n策略:利用被吃攒能量,关键时刻一口气刷新所有技能。",
			},
			{
				"board": [
					"RHEAKAEHR",
					".........",
					".C.....C.",
					"......P.P",
					".........",
					".........",
					"p.p.p.p.p",
					".c.....c.",
					".........",
					"rheakaehr",
				],
				"text": "使用后:己方其他技能全部完成冷却/充能(演示:所有主动技能立刻可用,皇后/死亡充能补满)。",
			},
		],
	},
	"zhanche2": {
		"steps": [
			{
				"board": [
					"RHEAKAEHR",
					".........",
					".C.....C.",
					"P.P.P.P.P",
					".........",
					".........",
					"p.p.p.p.p",
					".c.....c.",
					".........",
					"rheakaehr",
				],
				"text": "战车(逆位) · 主动 · 3回合\n用法:指定车相邻(不含对角)的己方棋子,落至车可落位。\n策略:同正位,但只认直线相邻的子。",
			},
			{
				"board": [
					"RHEAKAEHR",
					".........",
					".C.....C.",
					"P.P.P.P.P",
					".........",
					".........",
					"p.p.p.p.p",
					".c.....c.",
					".........",
					"r.ehkaehr",
				],
				"text": "使用后:车直线相邻的棋子被移到车可落位。",
			},
		],
	},
	"zhengyi2": {
		"steps": [
			{
				"board": [
					"RHEAKAEHR",
					".........",
					".C.....C.",
					"P.P.P.P.P",
					".........",
					".........",
					"p.p.p.p.p",
					".c.....c.",
					".........",
					"rheakaehr",
				],
				"text": "正义(逆位) · 主动 · 2回合\n用法:炮吃子变为隔两子;使用技能后在一子/两子间切换。\n策略:切换炮的打击距离,让对方防不胜防。",
			},
			{
				"board": [
					"RHEAKAEHR",
					".........",
					".C.....C.",
					"P.P.P.P.P",
					".........",
					".........",
					"p.p.p.p.p",
					".c.....c.",
					".........",
					"rheakaehr",
				],
				"text": "使用后:炮变为隔两子吃(演示:炮跳过两个棋子吃子)。",
			},
		],
	},
	"yinzhe2": {
		"steps": [
			{
				"board": [
					"RHEAKAEHR",
					".........",
					".C.....C.",
					"P.P.P.P.P",
					".........",
					".........",
					"p.p.p.p.p",
					".c.....c.",
					".........",
					"rheakaehr",
				],
				"text": "隐者(逆位) · 主动 · 12回合\n用法:敌我所有棋子进入隐身三回合。\n策略:全屏隐身——双方都看不到对方棋子,打信息战。",
			},
			{
				"board": [
					"RHEAKAEHR",
					".........",
					".C.....C.",
					"P.P.P.P.P",
					".........",
					".........",
					"p.p.p.p.p",
					".c.....c.",
					".........",
					"rheakaehr",
				],
				"text": "使用后:敌我所有子隐身三回合(演示:棋盘上棋子变透明)。",
			},
		],
	},
	"mingyun2": {
		"steps": [
			{
				"board": [
					"RHEAKAEHR",
					".........",
					".C.....C.",
					"P.P.P.P.P",
					".........",
					".........",
					"p.p.p.p.p",
					".c.....c.",
					".........",
					"rheakaehr",
				],
				"text": "命运之轮(逆位) · 主动 · 6回合\n用法:随机两枚己方棋子进入协同状态,下回合移动不消耗步数。\n策略:免费移动两子,快速布阵。",
			},
			{
				"board": [
					"RHEAKAEHR",
					".........",
					".C.....C.",
					"P.P.P.P.P",
					".........",
					".........",
					"p.p.p.p.p",
					".c.....c.",
					".........",
					"rheakaehr",
				],
				"text": "使用后:随机两子协同(演示:红马、红炮移动不耗步数)。",
			},
		],
	},
	"liliang2": {
		"steps": [
			{
				"board": [
					"RHEAKAEHR",
					".........",
					".C.....C.",
					"P.P.P.P.P",
					".........",
					".........",
					"p.p.p.p.p",
					".c.....c.",
					".........",
					"rheakaehr",
				],
				"text": "力量(逆位) · 被动\n用法:己方充能达到上限后仍可继续充能,最多累计至上限的3倍。\n策略:皇后/死亡等充能技能可囤积更多能量,关键时刻连续释放。",
			},
			{
				"board": [
					"RHEAKAEHR",
					".........",
					".C.....C.",
					"P.P.P.P.P",
					".........",
					".........",
					"p.p.p.p.p",
					".c.....c.",
					".........",
					"rheakaehr",
				],
				"text": "效果:皇后/死亡等充能技能达到上限后仍可继续累积(最高3倍,如皇后充能可到3,死亡可到9)。",
			},
		],
	},
	"diaodiao2": {
		"steps": [
			{
				"board": [
					"RHEAKAEHR",
					".........",
					".C.....C.",
					"P.P.P.P.P",
					".........",
					".........",
					"p.p.p.p.p",
					".c.....c.",
					".........",
					"rheakaehr",
				],
				"text": "倒吊人(逆位) · 主动 · 9回合\n用法:获得对方棋子控制权连续三回合,期间不能吃子。\n策略:长期控制对方关键子,让它瘫痪或当挡箭牌。",
			},
			{
				"board": [
					"RHEAKAEHR",
					".........",
					".C.....C.",
					"P.P.P.P.P",
					".........",
					".........",
					"p.p.p.p.p",
					".c.....c.",
					".........",
					"rheakaehr",
				],
				"text": "使用后:对方棋子被控制三回合(演示:黑車被控制,期间不能吃子)。",
			},
		],
	},
	"siwang2": {
		"steps": [
			{
				"board": [
					"RHEAKAEHR",
					".........",
					".C.....C.",
					"P.P.P.P.P",
					".........",
					".........",
					"p.p.p.p.p",
					".c.....c.",
					".........",
					"rheakaehr",
				],
				"text": "死亡(逆位) · 主动 · 被吃充能2\n用法:消耗 1 点充能,随机摧毁敌我各一子(将帅除外),己方有 50% 概率免疫摧毁。\n策略:赌运气的大杀器。",
			},
			{
				"board": [
					"R.EAKAEHR",
					".........",
					".C.....C.",
					"P.P.P.P.P",
					".........",
					".........",
					"p.p.p.p.p",
					".c.....c.",
					".........",
					"rheakae.r",
				],
				"text": "使用后:敌我随机各一子被摧毁(演示:随机目标消失)。",
			},
		],
	},
	"jiezhi2": {
		"steps": [
			{
				"board": [
					"RHEAKAEHR",
					".........",
					".C.....C.",
					"P.P.P.P.P",
					".........",
					".........",
					"p.p.p.p.p",
					".c.....c.",
					".........",
					"rheakaehr",
				],
				"text": "节制(逆位) · 主动\n用法:本回合追加一次行动,但下回合被跳过。\n策略:爆发一回合,代价是下回合停摆。",
			},
			{
				"board": [
					"RHEAKAEHR",
					".........",
					".C.....C.",
					"P.P.P.P.P",
					".........",
					".........",
					"p.p.p.p.p",
					".c.....c.",
					".........",
					"rheakaehr",
				],
				"text": "使用后:本回合追加行动,下回合跳过。",
			},
		],
	},
	"emo2": {
		"steps": [
			{
				"board": [
					"RHEAKAEHR",
					".........",
					".C.....C.",
					"P.P.P.P.P",
					".........",
					".........",
					"p.p.p.p.p",
					".c.....c.",
					".........",
					"rheakaehr",
				],
				"text": "恶魔(逆位) · 被动\n用法:敌方吃子后,我方对其他类型棋子的攻击全部免疫,直到 2 回合后或同类型子再次吃子。\n策略:对方吃子反而帮了你。",
			},
			{
				"board": [
					"RHEAKAEHR",
					".........",
					".C.....C.",
					"P.P.P.P.P",
					".........",
					".........",
					"p.p.p.p.p",
					".c.....c.",
					".........",
					"rheakaehr",
				],
				"text": "效果:对方吃子后我方获得 2 回合针对其他兵种的免疫。",
			},
		],
	},
	"ta2": {
		"steps": [
			{
				"board": [
					"RHEAKAEHR",
					".........",
					".C.....C.",
					"P.P.P.P.P",
					".........",
					".........",
					"p.p.p.p.p",
					".c.....c.",
					".........",
					"rheakaehr",
				],
				"text": "塔(逆位) · 被动 · 开局生效\n用法:开局失去所有兵;我方所有棋子可八向移动一格。\n策略:舍弃兵线,换取全子八向机动。",
			},
			{
				"board": [
					"RHEAKAEHR",
					".........",
					".C.....C.",
					"P.P.P.P.P",
					".........",
					".........",
					".........",
					".c.....c.",
					".........",
					"rheakaehr",
				],
				"text": "效果:开局无兵,所有子八向移动一格(演示:红方兵线清空)。",
			},
		],
	},
	"xingxing2": {
		"steps": [
			{
				"board": [
					"RHEAKAEHR",
					".........",
					".C.....C.",
					"P.P.P.P.P",
					".........",
					".........",
					"p.p.p.p.p",
					".c.....c.",
					".........",
					"rheakaehr",
				],
				"text": "星星(逆位) · 被动 · 每回合一次\n用法:同正位——每回合一次,兵/卒可无代价向后移动一格。",
			},
			{
				"board": [
					"RHEAKAEHR",
					".........",
					".C.....C.",
					"P.P.P.P.P",
					".........",
					".........",
					"p.p.p.p.p",
					".c.....c.",
					".........",
					"rheakaehr",
				],
				"text": "效果:兵可免费后退一格(蓝色退兵位)。",
			},
		],
	},
	"yueliang2": {
		"steps": [
			{
				"board": [
					"RHEAKAEHR",
					".........",
					".C.....C.",
					"P.P.P.P.P",
					".........",
					".........",
					"p.p.p.p.p",
					".c.....c.",
					".........",
					"rheakaehr",
				],
				"text": "月亮(逆位) · 被动 · 象强化\n用法:象的落位指示器为蓝色——移动到空格不消耗步数,移动完不结束本回合。\n策略:象可以无限白嫖移动,调整站位。",
			},
			{
				"board": [
					"RHEAKAEHR",
					".........",
					".C.....C.",
					"P.P.P.P.P",
					".........",
					".........",
					"p.p.p.p.p",
					".c.....c.",
					".........",
					"rheakaehr",
				],
				"text": "效果:象移到空格免费(蓝色指示器,不耗步数不结束回合)。",
			},
		],
	},
	"taiyang2": {
		"steps": [
			{
				"board": [
					"RHEAKAEHR",
					".........",
					".C.....C.",
					"P.P.P.P.P",
					".........",
					".........",
					"p.p.p.p.p",
					".c.....c.",
					".........",
					"rheakaehr",
				],
				"text": "太阳(逆位) · 被动 · 车强化\n用法:己方没有炮时,车变为八向无限距离移动。\n策略:舍炮保车,车变成超级武器。",
			},
			{
				"board": [
					"RHEAKAEHR",
					".........",
					".C.....C.",
					"P.P.P.P.P",
					".........",
					".........",
					"p.p.p.p.p",
					".c.....c.",
					".........",
					"rheakaehr",
				],
				"text": "效果:无炮时车八向无限移动(演示:红车可斜向长距离)。",
			},
		],
	},
	"shenpan2": {
		"steps": [
			{
				"board": [
					"RHEAKAEHR",
					".........",
					".C.....C.",
					"P.P.P.P.P",
					".........",
					".........",
					"p.p.p.p.p",
					".c.....c.",
					".........",
					"rheakaehr",
				],
				"text": "审判(逆位) · 被动\n用法:每回合使敌方失去一个技能,并重新随机抽取一个新技能。\n策略:不断搅乱对方技能配置。",
			},
			{
				"board": [
					"RHEAKAEHR",
					".........",
					".C.....C.",
					"P.P.P.P.P",
					".........",
					".........",
					"p.p.p.p.p",
					".c.....c.",
					".........",
					"rheakaehr",
				],
				"text": "效果:敌方失去一个技能并重抽。",
			},
		],
	},
	"shijie2": {
		"steps": [
			{
				"board": [
					"RHEAKAEHR",
					".........",
					".C.....C.",
					"P.P.P.P.P",
					".........",
					".........",
					"p.p.p.p.p",
					".c.....c.",
					".........",
					"rheakaehr",
				],
				"text": "世界(逆位) · 被动\n用法:每回合每个敌方棋子有 10% 概率变为任意棋子(将帅除外),弱子概率高、强子概率低。\n策略:让对方的棋子自己出问题。",
			},
			{
				"board": [
					"RHEAKAEHR",
					".........",
					".C.....C.",
					"H.P.P.P.P",
					".........",
					".........",
					"p.p.p.p.p",
					".c.....c.",
					".........",
					"rheakaehr",
				],
				"text": "效果:敌方棋子随机变型(演示:黑卒变为黑馬)。",
			},
		],
	},
}


# 技能使用建议/策略推荐
const STRATEGY := {
}


# ==================== 图鉴 UI ====================

var _font_cache: Font
var list_box: VBoxContainer
var current_id := ""
var info_title: Label
var info_tip: Label
var info_desc: Label
var _tip: Control            # 塔罗牌技能信息悬浮提示(共享)
var _info_card: TextureRect  # 中间:选中技能的大牌面


func _font() -> Font:
	if _font_cache == null:
		_font_cache = load("res://fonts/zpix.ttf")
	return _font_cache


func _ready() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.09, 0.08, 0.07)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var title := _make_label("技能图鉴", 40, Color(0.95, 0.85, 0.6))
	title.position = Vector2(0, 14)
	title.size = Vector2(1280, 48)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(title)

	var back := _make_button("返回菜单", Vector2(20, 20), Vector2(140, 42))
	back.pressed.connect(func(): Global.change_scene_with_fade("res://scenes/main.tscn"))
	add_child(back)

	# 左侧:44 张塔罗牌列表(4 列,可滚动)
	var list_bg := ColorRect.new()
	list_bg.color = Color(0.12, 0.11, 0.1)
	list_bg.position = Vector2(20, 80)
	list_bg.size = Vector2(460, 600)
	add_child(list_bg)
	var scroll := ScrollContainer.new()
	scroll.position = Vector2(20, 80)
	scroll.size = Vector2(460, 600)
	add_child(scroll)
	list_box = VBoxContainer.new()
	list_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(list_box)
	_build_list()

	# 中间:技能信息(大牌面 + 描述)
	var info_bg := ColorRect.new()
	info_bg.color = Color(0.13, 0.12, 0.11)
	info_bg.position = Vector2(500, 80)
	info_bg.size = Vector2(540, 560)
	add_child(info_bg)

	# 选中技能的大牌面(正位/逆位)
	_info_card = TextureRect.new()
	_info_card.position = Vector2(520, 100)
	_info_card.size = Tarot.card_size(200.0)
	_info_card.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_info_card.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_info_card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_info_card)

	info_title = _make_label("请选择左侧技能", 26, Color(0.95, 0.85, 0.6))
	info_title.position = Vector2(750, 110)
	info_title.size = Vector2(270, 40)
	info_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(info_title)

	info_tip = _make_label("", 15, Color(0.85, 0.75, 0.5))
	info_tip.position = Vector2(750, 158)
	info_tip.size = Vector2(270, 26)
	add_child(info_tip)

	info_desc = _make_label("", 15, Color(0.9, 0.88, 0.82))
	info_desc.position = Vector2(750, 196)
	info_desc.size = Vector2(270, 200)
	add_child(info_desc)

	# 最右侧:进入模拟对局(始终显示)
	var right_btn := _make_button("进入模拟对局", Vector2(1060, 320), Vector2(180, 56))
	right_btn.pressed.connect(_start_demo)
	add_child(right_btn)

	# 塔罗牌技能信息悬浮提示(共享,顶层)
	_tip = TarotTooltip.new()
	_tip.setup(_font())
	add_child(_tip)

	# 默认选中第一个技能(愚者)
	if not Perks.PERKS_NORMAL.is_empty():
		_select_skill(Perks.PERKS_NORMAL[0]["id"])
	Global.animate_ui_in(self)


func _build_list() -> void:
	var perks := Perks.load_perks("all")
	# 正位在前,逆位在后;牌面按 4 列网格排列
	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 12)
	grid.custom_minimum_size = Vector2(432, 0)
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list_box.add_child(grid)
	for row in Perks.PERKS_NORMAL + Perks.PERKS_ADVANCED:
		var id: String = row["id"]
		var info: Dictionary = perks[id]
		var card := TarotCard.new()
		card.setup(id, 0, info["name"], info.get("tip", ""), _full_desc(id), _font(), true, 100.0, _tip)
		card.set_sel_lift(false)  # 图鉴选中卡保持原位,不浮起
		card.set_meta("skill_id", id)
		card.clicked.connect(func(_sid: String, _s: int): _select_skill(_sid))
		grid.add_child(card)


# 高亮选中的技能卡(清除其他高亮,选中金色边框)
func _highlight_skill(id: String) -> void:
	if list_box == null:
		return
	for child in list_box.get_children():
		if not child is GridContainer:
			continue
		for c in child.get_children():
			if c.has_method("set_selected"):
				c.set_selected(str(c.get_meta("skill_id", "")) == id)


# 技能描述 + 策略建议(图鉴信息面板与悬浮提示共用)
func _full_desc(id: String) -> String:
	var perks := Perks.load_perks("all")
	var desc: String = perks.get(id, {}).get("desc", "")
	# 策略建议:优先用 STRATEGY 表,否则从演示文案提取"策略:"部分
	var strat: String = STRATEGY.get(id, "")
	if strat.is_empty():
		var steps: Array = DEMOS.get(id, {}).get("steps", [])
		if not steps.is_empty():
			var t: String = steps[0].get("text", "")
			if "策略:" in t:
				strat = t.split("策略:", 1)[1].split("\n")[0].strip_edges()
	if not strat.is_empty():
		desc += "\n\n策略建议:\n" + strat
	return desc


# 点击技能:显示技能描述与牌面(不立即进对局)
func _select_skill(id: String) -> void:
	_highlight_skill(id)
	current_id = id
	var perks := Perks.load_perks("all")
	var pk: Dictionary = perks.get(id, {})
	info_title.text = pk.get("name", id)
	info_tip.text = pk.get("tip", "")
	info_desc.text = _full_desc(id)
	# 中间大牌面:正位/逆位(逆位已烘焙翻转)
	_info_card.texture = Tarot.texture(id)


# 最右侧按钮:进入模拟对局(玩家拥有当前技能 vs 无技能机器人)
func _start_demo() -> void:
	if current_id.is_empty():
		return
	Global.demo_perk = current_id
	# 必须重置联机/存档残留:否则会走进联机分支或加载旧存档,回到上一局
	Global.game_mode = "ai"
	Global.net_role = "local"
	Global.load_slot = 0
	Global.from_lobby = false
	Global.change_scene_with_fade("res://scenes/game.tscn")


func _make_label(text: String, size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", _font())
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return l


func _make_button(text: String, pos: Vector2, size: Vector2) -> Button:
	var b := Button.new()
	b.text = text
	b.position = pos
	b.size = size
	b.add_theme_font_override("font", _font())
	b.add_theme_font_size_override("font_size", 16)
	# 透明背景 + 悬浮变黄;文字右移 8px
	var normal := StyleBoxFlat.new()
	normal.bg_color = Color(0, 0, 0, 0)
	normal.set_corner_radius_all(4)
	normal.content_margin_left = 8.0
	b.add_theme_stylebox_override("normal", normal)
	b.add_theme_stylebox_override("hover", normal)
	b.add_theme_stylebox_override("pressed", normal)
	b.add_theme_stylebox_override("focus", normal)
	b.add_theme_stylebox_override("hover_pressed", normal)
	b.add_theme_color_override("font_color", Color(0.85, 0.82, 0.75))
	b.add_theme_color_override("font_hover_color", Color(1.0, 0.9, 0.3))
	b.add_theme_color_override("font_pressed_color", Color(1.0, 0.85, 0.2))
	return b
