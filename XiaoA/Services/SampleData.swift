import Foundation

#if DEBUG
extension AppConfig {
    /// Made-up details so every screen looks real in the simulator.
    /// Only used by debug builds running in the simulator, never on a real phone.
    static var simulatorSample: AppConfig {
        var c = AppConfig()
        c.momNameZH = "妈妈"
        c.momNameEN = "Mei"
        c.momPhone = "(408) 555-0188"
        c.alexName = "Alex"
        c.alexPhone = "(408) 555-0134"
        c.homeAddressEN = "123 Sample Street, San Jose, CA 95112"
        c.homeAddressZH = "圣何塞 Sample 街 123 号"
        c.places = [
            Place(nameZH: "超市", addressEN: "100 Main Street, San Jose, CA 95113", icon: "cart.fill"),
            Place(nameZH: "公园", addressEN: "50 Park Avenue, San Jose, CA 95110", icon: "leaf.fill"),
            Place(nameZH: "诊所", addressEN: "300 Health Way, San Jose, CA 95128", icon: "cross.case.fill"),
            Place(nameZH: "中餐馆", addressEN: "88 Lucky Street, San Jose, CA 95112", icon: "fork.knife")
        ]
        c.medical.insurer = "Sample Health Plan"
        c.medical.memberID = "SAMPLE-000000"
        c.medical.policyNumber = "GRP-0000"
        c.medical.insurerPhone = "(800) 555-0100"
        c.medical.conditionsEN = "None known"
        c.medical.conditionsZH = "无"
        c.medical.medicationsEN = "None"
        c.medical.medicationsZH = "无"
        c.medical.allergiesEN = "No known allergies"
        c.medical.allergiesZH = "没有已知过敏"
        c.medical.doctorName = "Dr. Sample"
        c.medical.doctorPhone = "(408) 555-0170"
        return c
    }
}
#endif
