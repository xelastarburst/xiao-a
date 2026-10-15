import Foundation

struct Phrase: Identifiable, Hashable {
    let id: String
    /// What she says.
    let en: String
    /// What it means.
    let zh: String
    /// When she'd say it.
    let scene: String
    /// Beats with the stressed one in capitals, e.g. "where · is · the · REST·room".
    let beats: String
}

struct LessonUnit: Identifiable {
    let id: Int
    let title: String
    let phrases: [Phrase]
}

/// Survival English for a total beginner, ordered by how soon she'll need it.
/// About 175 phrases: at 4 new a day plus review, that's 6–7 weeks of new material,
/// then review keeps going for the rest of the visit. Bundled so lessons work offline.
/// Phrase ids are stable — progress is saved by id, so reordering units is safe.
enum Curriculum {
    static func units(for config: AppConfig) -> [LessonUnit] {
        let alex = config.alexName.isEmpty ? "Alex" : config.alexName
        var aboutMe: [Phrase] = [
            p("me1", "Nice to meet you.", "很高兴认识你。", "第一次见到邻居或朋友", "nice · to · MEET · you")
        ]
        if !config.momNameEN.isEmpty {
            aboutMe.append(p("me2", "My name is \(config.momNameEN).", "我的名字是 \(config.momNameEN)。",
                             "别人问你叫什么", "my · name · is · \(config.momNameEN.uppercased())"))
        }
        aboutMe += [
            p("me3", "I speak Chinese.", "我说中文。", "告诉别人你说什么语言", "i · speak · chi·NESE"),
            p("me4", "I am visiting my son.", "我来看我儿子。", "别人问你为什么来美国", "i · am · VIS·it·ing · my · SON"),
            p("me5", "My son's name is \(alex).", "我儿子叫 \(alex)。", "别人问你儿子是谁", "my · son's · name · is · \(alex.uppercased())"),
            p("me6", "Please call my son.", "请给我儿子打电话。", "需要别人帮你联系儿子", "please · CALL · my · son")
        ]

        return [
            // MARK: Week 1 — the basics she needs on day one
            LessonUnit(id: 1, title: "打招呼和礼貌", phrases: [
                p("g1", "Hello!", "你好！", "见到人打招呼", "hel·LO"),
                p("g2", "Good morning!", "早上好！", "早上见到邻居", "good · MOR·ning"),
                p("g3", "Thank you!", "谢谢你！", "别人帮了你", "THANK · you"),
                p("g4", "You're welcome.", "不客气。", "别人跟你说谢谢", "you're · WEL·come"),
                p("g5", "Excuse me.", "打扰一下。", "想从别人旁边过去，或者想问问题", "ex·CUSE · me"),
                p("g6", "Sorry!", "对不起！", "不小心碰到别人", "SOR·ry")
            ]),
            LessonUnit(id: 2, title: "最有用的几句话", phrases: [
                p("s1", "I don't speak English.", "我不会说英语。", "别人跟你说英语，你听不懂", "i · DON'T · speak · ENG·lish"),
                p("s2", "I don't understand.", "我听不懂。", "对方说得太快", "i · don't · un·der·STAND"),
                p("s3", "Please speak slowly.", "请说慢一点。", "想让对方说慢一点", "please · speak · SLOW·ly"),
                p("s4", "Yes, please.", "好的，谢谢。", "别人问你要不要", "YES · please"),
                p("s5", "No, thank you.", "不用了，谢谢。", "你不需要的时候", "NO · thank · you"),
                p("s6", "Help, please!", "请帮帮我！", "需要别人帮忙", "HELP · please")
            ]),
            LessonUnit(id: 3, title: "听不懂的时候", phrases: [
                p("x1", "Can you say that again?", "你能再说一遍吗？", "没听清楚", "can · you · say · that · a·GAIN"),
                p("x2", "Can you write it down?", "你能写下来吗？", "听不懂，想让对方写下来", "can · you · WRITE · it · down"),
                p("x3", "Please show me.", "请指给我看。", "想让对方指一下", "please · SHOW · me"),
                p("x4", "What does this mean?", "这是什么意思？", "看不懂一个词", "what · does · this · MEAN"),
                p("x5", "Sorry, I don't know.", "对不起，我不知道。", "别人问你不知道的事", "sor·ry · i · don't · KNOW"),
                p("x6", "Let me use my phone.", "我用手机翻译一下。", "拿出小A 来翻译", "let · me · use · my · PHONE")
            ]),
            LessonUnit(id: 4, title: "介绍自己", phrases: aboutMe),
            LessonUnit(id: 5, title: "紧急情况", phrases: [
                p("e1", "Mandarin, please.", "请找普通话翻译。", "打 911 的时候先说这句", "MAN·da·rin · please"),
                p("e2", "I need help.", "我需要帮助。", "遇到麻烦", "i · need · HELP"),
                p("e3", "I am lost.", "我迷路了。", "找不到路", "i · am · LOST"),
                p("e4", "Please call 911.", "请帮我打 911。", "请别人帮你打电话", "please · call · nine · one · ONE"),
                p("e5", "Call an ambulance!", "叫救护车！", "有人受伤或生病", "call · an · AM·bu·lance"),
                p("e6", "Please wait.", "请等一下。", "需要对方等你", "please · WAIT")
            ]),

            // MARK: Weeks 2–3 — everyday errands
            LessonUnit(id: 6, title: "数字和钱", phrases: [
                p("n1", "How much is this?", "这个多少钱？", "在商店想知道价格", "how · MUCH · is · this"),
                p("n2", "One, two, three.", "一、二、三。", "练习数字", "ONE · TWO · THREE"),
                p("n3", "Five dollars.", "五美元。", "听懂或者说价格", "FIVE · DOL·lars"),
                p("n4", "Can I pay by card?", "可以刷卡吗？", "结账的时候", "can · i · pay · by · CARD"),
                p("n5", "Cash, please.", "我付现金。", "结账的时候", "CASH · please"),
                p("n6", "Keep the change.", "不用找零了。", "给小费或者不要零钱", "keep · the · CHANGE")
            ]),
            LessonUnit(id: 7, title: "超市购物", phrases: [
                p("m1", "Where is the restroom?", "洗手间在哪里？", "在超市，你想上厕所", "where · is · the · REST·room"),
                p("m2", "Where is the milk?", "牛奶在哪里？", "找不到想买的东西", "where · is · the · MILK"),
                p("m3", "I'm just looking.", "我只是看看。", "店员问你需要什么", "i'm · just · LOOK·ing"),
                p("m4", "Do you have a bag?", "有袋子吗？", "结账的时候", "do · you · have · a · BAG"),
                p("m5", "Is this on sale?", "这个打折吗？", "看到喜欢的东西", "is · this · on · SALE"),
                p("m6", "That's all, thank you.", "就这些，谢谢。", "买完了", "that's · ALL · thank · you")
            ]),
            LessonUnit(id: 8, title: "点餐和咖啡", phrases: [
                p("f1", "A coffee, please.", "请给我一杯咖啡。", "在咖啡店点单", "a · COF·fee · please"),
                p("f2", "Hot water, please.", "请给我热水。", "想喝热水", "HOT · wa·ter · please"),
                p("f3", "To go, please.", "我要带走。", "店员问 for here or to go", "to · GO · please"),
                p("f4", "For here.", "在这里吃。", "店员问 for here or to go", "for · HERE"),
                p("f5", "No ice, please.", "不要冰。", "点饮料的时候", "NO · ICE · please"),
                p("f6", "The check, please.", "请结账。", "在餐厅吃完饭", "the · CHECK · please")
            ]),
            LessonUnit(id: 9, title: "打车和问路", phrases: [
                p("r1", "Please take me home.", "请带我回家。", "坐上车以后跟司机说", "please · take · me · HOME"),
                p("r2", "Is this my car?", "这是我的车吗？", "上车前问司机", "is · this · MY · car"),
                p("r3", "Stop here, please.", "请在这里停。", "快到了，想下车", "STOP · here · please"),
                p("r4", "Turn left, please.", "请左转。", "给司机指路", "turn · LEFT · please"),
                p("r5", "How do I get there?", "我怎么去那里？", "问路", "how · do · i · get · THERE"),
                p("r6", "Where is the bus stop?", "公交车站在哪里？", "找公交车站", "where · is · the · BUS · stop")
            ]),
            LessonUnit(id: 10, title: "药店和看病", phrases: [
                p("d1", "I feel sick.", "我不舒服。", "身体不舒服的时候", "i · feel · SICK"),
                p("d2", "It hurts here.", "这里疼。", "指着疼的地方", "it · HURTS · here"),
                p("d3", "I need a doctor.", "我需要看医生。", "想看医生", "i · need · a · DOC·tor"),
                p("d4", "Here is my insurance card.", "这是我的保险卡。", "在诊所或医院", "here · is · my · in·SUR·ance · card"),
                p("d5", "Where is the pharmacy?", "药店在哪里？", "找药店", "where · is · the · PHAR·ma·cy"),
                p("d6", "How many times a day?", "一天吃几次？", "问药怎么吃", "how · many · TIMES · a · day")
            ]),
            LessonUnit(id: 11, title: "和邻居聊天", phrases: [
                p("t1", "How are you?", "你好吗？", "见到认识的人", "how · ARE · you"),
                p("t2", "I'm fine, thank you.", "我很好，谢谢。", "别人问你好不好", "i'm · FINE · thank · you"),
                p("t3", "Nice weather today!", "今天天气真好！", "和邻居聊天", "nice · WEA·ther · to·DAY"),
                p("t4", "What's your name?", "你叫什么名字？", "想知道对方名字", "what's · your · NAME"),
                p("t5", "See you later!", "回头见！", "说再见", "see · you · LA·ter"),
                p("t6", "Have a nice day!", "祝你今天愉快！", "分开的时候", "have · a · nice · DAY")
            ]),
            LessonUnit(id: 12, title: "时间和预约", phrases: [
                p("c1", "What time is it?", "现在几点？", "想知道时间", "what · TIME · is · it"),
                p("c2", "Ten o'clock.", "十点钟。", "说时间", "TEN · o'·CLOCK"),
                p("c3", "I have an appointment.", "我有预约。", "到诊所或银行", "i · have · an · ap·POINT·ment"),
                p("c4", "Is it open on Sunday?", "星期天开门吗？", "问营业时间", "is · it · O·pen · on · SUN·day"),
                p("c5", "See you tomorrow.", "明天见。", "说再见", "see · you · to·MOR·row"),
                p("c6", "One moment, please.", "请稍等。", "需要对方等一下", "one · MO·ment · please")
            ]),
            LessonUnit(id: 13, title: "安全", phrases: [
                p("sf1", "Stop!", "住手！/停下！", "有人做你不想要的事", "STOP"),
                p("sf2", "Leave me alone!", "别管我！", "有人纠缠你", "leave · me · a·LONE"),
                p("sf3", "Call the police!", "叫警察！", "遇到危险", "call · the · po·LICE"),
                p("sf4", "I don't know you.", "我不认识你。", "陌生人跟你搭话要东西", "i · don't · KNOW · you"),
                p("sf5", "I don't have money.", "我没有钱。", "陌生人跟你要钱", "i · don't · have · MON·ey"),
                p("sf6", "Is it safe here?", "这里安全吗？", "到一个陌生地方", "is · it · SAFE · here")
            ]),

            // MARK: Weeks 4–5 — more confidence out and about
            LessonUnit(id: 14, title: "超市买菜", phrases: [
                p("gr1", "Where are the eggs?", "鸡蛋在哪里？", "在超市找东西", "where · are · the · EGGS"),
                p("gr2", "Where is the rice?", "大米在哪里？", "在超市找东西", "where · is · the · RICE"),
                p("gr3", "Is this fresh?", "这个新鲜吗？", "买菜买肉的时候", "is · this · FRESH"),
                p("gr4", "One pound, please.", "请给我一磅。", "在肉柜、菜柜称重", "one · POUND · please"),
                p("gr5", "Do you have tofu?", "有豆腐吗？", "找不到想买的东西", "do · you · have · TO·fu"),
                p("gr6", "Paper, please.", "纸袋，谢谢。", "店员问 paper or plastic", "PA·per · please")
            ]),
            LessonUnit(id: 15, title: "买衣服和日用品", phrases: [
                p("b1", "Do you have a smaller size?", "有小一点的吗？", "买衣服鞋子", "do · you · have · a · SMALL·er · size"),
                p("b2", "Can I try it on?", "我可以试穿吗？", "买衣服", "can · i · TRY · it · on"),
                p("b3", "Where do I pay?", "在哪里付钱？", "找收银台", "where · do · i · PAY"),
                p("b4", "I need a receipt.", "我要收据。", "付完钱", "i · need · a · re·CEIPT"),
                p("b5", "Can I return this?", "这个可以退吗？", "想退货", "can · i · re·TURN · this"),
                p("b6", "It's too expensive.", "太贵了。", "觉得价格高", "it's · too · ex·PEN·sive")
            ]),
            LessonUnit(id: 16, title: "在餐厅", phrases: [
                p("o1", "A table for two, please.", "请给我们两个人的桌子。", "走进餐厅", "a · TA·ble · for · TWO · please"),
                p("o2", "Can I see the menu?", "可以看看菜单吗？", "坐下以后", "can · i · see · the · MEN·u"),
                p("o3", "I'll have this one.", "我要这个。", "指着菜单点菜", "i'll · have · THIS · one"),
                p("o4", "Not spicy, please.", "请不要辣。", "点菜的时候", "NOT · SPI·cy · please"),
                p("o5", "Can I have a box?", "可以给我一个打包盒吗？", "吃不完想打包", "can · i · have · a · BOX"),
                p("o6", "It was delicious!", "很好吃！", "吃完夸一句", "it · was · de·LI·cious")
            ]),
            LessonUnit(id: 17, title: "问路", phrases: [
                p("w1", "Is it far?", "远吗？", "别人告诉你一个地方", "is · it · FAR"),
                p("w2", "Can I walk there?", "走路能到吗？", "问路", "can · i · WALK · there"),
                p("w3", "Go straight.", "直走。", "听懂别人指路", "go · STRAIGHT"),
                p("w4", "Turn right.", "右转。", "听懂别人指路", "turn · RIGHT"),
                p("w5", "It's on the left.", "在左边。", "听懂别人指路", "it's · on · the · LEFT"),
                p("w6", "Where is the train station?", "火车站在哪里？", "找火车站", "where · is · the · TRAIN · sta·tion")
            ]),
            LessonUnit(id: 18, title: "坐公交和火车", phrases: [
                p("p1", "Does this bus go downtown?", "这辆车去市中心吗？", "上车前问司机", "does · this · BUS · go · down·TOWN"),
                p("p2", "One ticket, please.", "一张票。", "买票", "one · TICK·et · please"),
                p("p3", "Please tell me when to get off.", "到站请告诉我。", "怕坐过站", "please · tell · me · when · to · get · OFF"),
                p("p4", "Is this seat free?", "这里有人坐吗？", "想坐下", "is · this · SEAT · free"),
                p("p5", "This is my stop.", "我要在这站下车。", "到站了", "this · is · my · STOP"),
                p("p6", "How long does it take?", "要多长时间？", "问路程时间", "how · LONG · does · it · take")
            ]),
            LessonUnit(id: 19, title: "在家门口", phrases: [
                p("h1", "Who is it?", "是谁？", "听到敲门", "WHO · is · it"),
                p("h2", "Come in, please.", "请进。", "朋友来了", "come · IN · please"),
                p("h3", "My son is not home.", "我儿子不在家。", "有人来找儿子", "my · son · is · NOT · home"),
                p("h4", "Please leave it at the door.", "请放在门口。", "快递员来了", "please · leave · it · at · the · DOOR"),
                p("h5", "I don't need anything, thank you.", "我什么都不需要，谢谢。", "推销员上门", "i · don't · need · AN·y·thing · thank · you"),
                p("h6", "Please come back later.", "请晚点再来。", "不方便开门", "please · come · back · LA·ter")
            ]),
            LessonUnit(id: 20, title: "身体和感觉", phrases: [
                p("bd1", "I'm tired.", "我累了。", "走累了想休息", "i'm · TIRED"),
                p("bd2", "I'm hungry.", "我饿了。", "想吃东西", "i'm · HUN·gry"),
                p("bd3", "I'm thirsty.", "我渴了。", "想喝水", "i'm · THIRS·ty"),
                p("bd4", "I'm cold.", "我冷。", "觉得冷", "i'm · COLD"),
                p("bd5", "I feel dizzy.", "我头晕。", "身体不舒服", "i · feel · DIZ·zy"),
                p("bd6", "I need to sit down.", "我需要坐一下。", "站不稳或累了", "i · need · to · SIT · down")
            ]),
            LessonUnit(id: 21, title: "看医生", phrases: [
                p("dr1", "I have a headache.", "我头疼。", "跟医生说哪里不舒服", "i · have · a · HEAD·ache"),
                p("dr2", "My stomach hurts.", "我肚子疼。", "跟医生说哪里不舒服", "my · STOM·ach · hurts"),
                p("dr3", "I have a fever.", "我发烧了。", "跟医生说哪里不舒服", "i · have · a · FE·ver"),
                p("dr4", "I take this medicine.", "我吃这个药。", "给医生看你的药", "i · take · this · MED·i·cine"),
                p("dr5", "I am allergic to this.", "我对这个过敏。", "指着过敏的东西", "i · am · al·LER·gic · to · this"),
                p("dr6", "I need an interpreter.", "我需要翻译。", "在医院、诊所", "i · need · an · in·TER·pre·ter")
            ]),

            // MARK: Weeks 6–7 — daily life and small talk
            LessonUnit(id: 22, title: "天气", phrases: [
                p("a1", "It's hot today.", "今天很热。", "和别人聊天气", "it's · HOT · to·day"),
                p("a2", "It's cold today.", "今天很冷。", "和别人聊天气", "it's · COLD · to·day"),
                p("a3", "It's raining.", "下雨了。", "出门看到下雨", "it's · RAIN·ing"),
                p("a4", "It's sunny.", "今天出太阳了。", "天气很好", "it's · SUN·ny"),
                p("a5", "Is it going to rain?", "会下雨吗？", "出门前", "is · it · going · to · RAIN"),
                p("a6", "I need a jacket.", "我需要一件外套。", "觉得冷", "i · need · a · JACK·et")
            ]),
            LessonUnit(id: 23, title: "家人", phrases: [
                p("fa1", "This is my son.", "这是我儿子。", "给别人介绍儿子", "this · is · my · SON"),
                p("fa2", "I am his mother.", "我是他妈妈。", "别人问你是谁", "i · am · his · MOTH·er"),
                p("fa3", "This is my family.", "这是我的家人。", "给别人看照片", "this · is · my · FAM·i·ly"),
                p("fa4", "He works here.", "他在这里工作。", "聊到儿子", "he · WORKS · here"),
                p("fa5", "We live together.", "我们住在一起。", "别人问你住哪里", "we · live · to·GETH·er"),
                p("fa6", "I miss home.", "我想家了。", "聊天的时候", "i · miss · HOME")
            ]),
            LessonUnit(id: 24, title: "公园和散步", phrases: [
                p("pk1", "Good afternoon!", "下午好！", "下午遇到人", "good · af·ter·NOON"),
                p("pk2", "What a cute dog!", "好可爱的狗！", "遇到遛狗的邻居", "what · a · CUTE · dog"),
                p("pk3", "Can I sit here?", "我可以坐这里吗？", "公园长椅有人", "can · i · SIT · here"),
                p("pk4", "Where is the park?", "公园在哪里？", "想去散步", "where · is · the · PARK"),
                p("pk5", "I walk every day.", "我每天散步。", "和邻居聊天", "i · WALK · ev·ery · day"),
                p("pk6", "Have a good evening!", "晚上愉快！", "傍晚说再见", "have · a · good · EVE·ning")
            ]),
            LessonUnit(id: 25, title: "打电话", phrases: [
                p("ph1", "Hello, this is \(alex)'s mom.", "你好，我是 \(alex) 的妈妈。", "接电话或打电话", "hel·LO · this · is · \(alex.uppercased())'S · MOM"),
                p("ph2", "I can't hear you.", "我听不清。", "电话里听不清", "i · CAN'T · hear · you"),
                p("ph3", "Please call back later.", "请晚点再打来。", "现在不方便", "please · call · back · LA·ter"),
                p("ph4", "Wrong number.", "打错了。", "陌生人打错电话", "WRONG · num·ber"),
                p("ph5", "Please text me.", "请给我发短信。", "电话里听不懂", "please · TEXT · me"),
                p("ph6", "Goodbye!", "再见！", "挂电话", "good·BYE")
            ]),
            LessonUnit(id: 26, title: "银行和邮局", phrases: [
                p("k1", "I want to mail this.", "我要寄这个。", "在邮局", "i · want · to · MAIL · this"),
                p("k2", "How much is a stamp?", "一张邮票多少钱？", "在邮局", "how · much · is · a · STAMP"),
                p("k3", "Where is the ATM?", "取款机在哪里？", "想取钱", "where · is · the · A·T·M"),
                p("k4", "I don't have cash.", "我没有现金。", "付钱的时候", "i · don't · have · CASH"),
                p("k5", "Can I use this card?", "可以用这张卡吗？", "付钱的时候", "can · i · use · this · CARD"),
                p("k6", "Where do I sign?", "我在哪里签名？", "需要签字的时候", "where · do · i · SIGN")
            ]),
            LessonUnit(id: 27, title: "数量", phrases: [
                p("nn1", "How many?", "多少个？", "想知道数量", "how · MAN·y"),
                p("nn2", "Two, please.", "请给我两个。", "买东西", "TWO · please"),
                p("nn3", "Just one.", "只要一个。", "买东西", "just · ONE"),
                p("nn4", "Twenty dollars.", "二十美元。", "听懂或者说价格", "TWEN·ty · dol·lars"),
                p("nn5", "Fifty cents.", "五十美分。", "听懂零钱", "FIF·ty · cents"),
                p("nn6", "That's too much.", "太多了。", "给的太多了", "that's · too · MUCH")
            ]),
            LessonUnit(id: 28, title: "星期和日期", phrases: [
                p("dt1", "What day is today?", "今天星期几？", "想知道星期几", "what · DAY · is · to·day"),
                p("dt2", "Today is Monday.", "今天星期一。", "说星期几", "to·day · is · MON·day"),
                p("dt3", "See you next week.", "下周见。", "说再见", "see · you · next · WEEK"),
                p("dt4", "In the morning.", "上午。", "约时间", "in · the · MOR·ning"),
                p("dt5", "In the afternoon.", "下午。", "约时间", "in · the · af·ter·NOON"),
                p("dt6", "Tomorrow at ten.", "明天十点。", "约时间", "to·MOR·row · at · TEN")
            ]),
            LessonUnit(id: 29, title: "客气话", phrases: [
                p("pr1", "No problem.", "没问题。", "别人请你帮忙", "no · PROB·lem"),
                p("pr2", "Of course.", "当然。", "答应别人", "of · COURSE"),
                p("pr3", "Me too.", "我也是。", "和别人一样", "me · TOO"),
                p("pr4", "Sorry to bother you.", "不好意思打扰你。", "请陌生人帮忙", "sor·ry · to · BOTH·er · you"),
                p("pr5", "That's very kind of you.", "你真好。", "别人帮了你", "that's · very · KIND · of · you"),
                p("pr6", "Take care!", "保重！", "分开的时候", "take · CARE")
            ])
        ]
    }

    static func allPhrases(for config: AppConfig) -> [Phrase] {
        units(for: config).flatMap(\.phrases)
    }

    static func unitTitle(of phraseID: String, config: AppConfig) -> String? {
        units(for: config).first(where: { $0.phrases.contains(where: { $0.id == phraseID }) })?.title
    }

    private static func p(_ id: String, _ en: String, _ zh: String, _ scene: String, _ beats: String) -> Phrase {
        Phrase(id: id, en: en, zh: zh, scene: scene, beats: beats)
    }
}
