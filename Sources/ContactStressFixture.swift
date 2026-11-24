import Foundation

/// Local-only address-book fixture for validating large contact projections.
enum ContactStressFixture {
    static let count = StressTestConfiguration.contactCount
    static let isActive = count > 0

    private static let names = [
        "安", "白", "陈", "邓", "方", "高", "何", "黄", "江", "孔",
        "李", "林", "刘", "马", "潘", "钱", "任", "孙", "唐", "王",
        "吴", "徐", "杨", "张", "赵", "周", "郑", "冯", "许", "谢",
        "宋", "沈", "韩", "曹", "彭", "曾", "田", "董", "袁", "蔡"
    ]

    static let contacts: [User] = (0..<count).map { index in
        let given = names[index % names.count]
        let display = "\(given)联系人\(index + 1)"
        return User(
            id: "stress-contact-\(index)",
            nickname: display,
            avatar: ""
        )
    }
}
