import Foundation

#if DEBUG
extension AppConfig {
    /// Made-up details so every screen looks real in the simulator.
    /// Only used by debug builds running in the simulator, never on a real phone.
    static var simulatorSample: AppConfig {
        var c = AppConfig()
        c.herName = "Frau Weber"
        c.herNameEN = "Inge Weber"
        c.herPhone = "(408) 555-0188"
        c.contactName = "Sabine"
        c.contactPhone = "(408) 555-0134"
        c.homeAddressEN = "123 Sample Street, San Jose, CA 95112"
        c.homeAddressDE = "123 Sample Street, San Jose"
        c.places = [
            Place(nameDE: "Supermarkt", addressEN: "100 Main Street, San Jose, CA 95113", icon: "cart.fill"),
            Place(nameDE: "Park", addressEN: "50 Park Avenue, San Jose, CA 95110", icon: "leaf.fill"),
            Place(nameDE: "Arztpraxis", addressEN: "300 Health Way, San Jose, CA 95128", icon: "cross.case.fill"),
            Place(nameDE: "Bäckerei", addressEN: "88 Bread Street, San Jose, CA 95112", icon: "fork.knife")
        ]
        c.medical.insurer = "Sample Health Plan"
        c.medical.memberID = "SAMPLE-000000"
        c.medical.policyNumber = "GRP-0000"
        c.medical.insurerPhone = "(800) 555-0100"
        c.medical.conditionsEN = "None known"
        c.medical.conditionsDE = "Keine bekannt"
        c.medical.medicationsEN = "None"
        c.medical.medicationsDE = "Keine"
        c.medical.allergiesEN = "No known allergies"
        c.medical.allergiesDE = "Keine bekannten Allergien"
        c.medical.doctorName = "Dr. Sample"
        c.medical.doctorPhone = "(408) 555-0170"
        return c
    }
}
#endif
