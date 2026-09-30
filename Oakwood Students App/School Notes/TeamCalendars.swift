//
//  TeamCalendars.swift
//  School Notes
//
//  Created by Luke Titi on 2/4/26.
//

import Foundation

struct TeamCalendar {
    let name: String
    let sport: String
    let url: String
}

struct SchoolCalendarFeed {
    let category: String
    let url: String
}

// Oakwood's public school-level event calendars (Finalsite-hosted) — separate feeds per
// level so events can be tagged and filtered like sports already are. The old Veracross
// feed only had generic scheduling milestones (trimester/semester begin markers,
// bell-schedule day-type labels) and was missing most real events entirely.
let schoolEventCalendars: [SchoolCalendarFeed] = [
    SchoolCalendarFeed(category: "High School", url: "https://www.oakwoodway.org/calendar/calendar_2811.ics"),
    SchoolCalendarFeed(category: "Middle School", url: "https://www.oakwoodway.org/calendar/calendar_2810.ics"),
    SchoolCalendarFeed(category: "Lower School", url: "https://www.oakwoodway.org/calendar/calendar_2809.ics"),
    SchoolCalendarFeed(category: "College Counseling", url: "https://www.oakwoodway.org/calendar/calendar_2816.ics"),
    SchoolCalendarFeed(category: "College Visits", url: "https://www.oakwoodway.org/calendar/calendar_2817.ics"),
]

// Veracross mints a brand-new team/roster record (and a brand-new .ics subscribe link) for
// every season — last year's links keep resolving (200 OK, valid iCal) but never gain new
// games, since they're a genuinely different team object. These were re-pulled directly from
// the portal's own "Calendar Subscriptions" page (Athletics section) for the current season —
// see the equivalent page inside portals.veracross.com/oakwood if these ever go stale again.
let teamCalendars: [TeamCalendar] = [
    // Basketball - Boys
    TeamCalendar(name: "Boys Varsity Basketball", sport: "Basketball", url: "https://api.veracross.com/oakwood/teams/63349.ics?t=f6e9cca7fb383ab3d8330c95f134afd0&uid=784F2C61-9363-49C1-BFEC-7EDD4A397267"),
    TeamCalendar(name: "Boys JV Basketball", sport: "Basketball", url: "https://api.veracross.com/oakwood/teams/63348.ics?t=801e3760305fa51b5acc0916778db411&uid=CAF0363D-F1BF-4ECA-8295-C68277B76B8D"),
    TeamCalendar(name: "Boys Frosh Soph Basketball", sport: "Basketball", url: "https://api.veracross.com/oakwood/teams/63354.ics?t=53bdfeaf6d8d5e9e89c55c8223a9a51a&uid=6D49E771-1A1C-4703-9601-6BD6E19E59D3"),
    TeamCalendar(name: "6th/7th Boys Basketball Green", sport: "Basketball", url: "https://api.veracross.com/oakwood/teams/63340.ics?t=017a73788506532e879aa00a377dd40d&uid=E41D0B5B-9693-4B45-97FF-26BD655C2304"),
    TeamCalendar(name: "6th/7th Boys Basketball White", sport: "Basketball", url: "https://api.veracross.com/oakwood/teams/63341.ics?t=e6afd1af318d7803a9f624d98e4c5f96&uid=21B10858-3AA8-4BCD-BB72-29CF66B75488"),
    TeamCalendar(name: "Boys 6th Grade Basketball", sport: "Basketball", url: "https://api.veracross.com/oakwood/teams/63331.ics?t=7d10d4e7516184ef9288da388b3df8f1&uid=78DA925A-F033-4ED8-A96A-AE5F1F6DC436"),
    TeamCalendar(name: "Boys 7th Grade Basketball Green", sport: "Basketball", url: "https://api.veracross.com/oakwood/teams/63342.ics?t=1db012ac8b73f5a55e6d60a0879809a3&uid=7D160059-8046-41F7-8D03-2EBB59CB4EB6"),
    TeamCalendar(name: "Boys 7th Grade Basketball", sport: "Basketball", url: "https://api.veracross.com/oakwood/teams/63333.ics?t=17fddf0ae4646243257ed9da3b115fdc&uid=076CA704-3F7F-4C2A-953B-C22D99286658"),
    TeamCalendar(name: "Boys 8th Grade Basketball", sport: "Basketball", url: "https://api.veracross.com/oakwood/teams/63338.ics?t=0f6716b2d5c0dada3966096a3690f35e&uid=94ED49B2-C4E7-46CF-88AE-D96914642A34"),

    // Basketball - Girls
    TeamCalendar(name: "Girls Varsity Basketball", sport: "Basketball", url: "https://api.veracross.com/oakwood/teams/63350.ics?t=20fb6e6c02b6f76c248145d9f6945895&uid=273B641A-E6D0-4C32-8BBF-75FB294C5119"),
    TeamCalendar(name: "Girls MS Basketball", sport: "Basketball", url: "https://api.veracross.com/oakwood/teams/63332.ics?t=c14eca4e73339b149d2f3d68aec572ca&uid=E698F399-7031-4504-BF94-DF9862CFA60B"),

    // Soccer
    TeamCalendar(name: "Boys Varsity Soccer", sport: "Soccer", url: "https://api.veracross.com/oakwood/teams/63347.ics?t=e24f2ced729b4292d26751978fa31264&uid=5E8F3079-5AF1-4DE8-B94B-2C66A1032AAE"),
    TeamCalendar(name: "Girls Varsity Soccer", sport: "Soccer", url: "https://api.veracross.com/oakwood/teams/63353.ics?t=02f6002f237d2376cc0d21d5e16da400&uid=FF1AE7E4-307E-4BA1-8A93-529B216A945D"),
    TeamCalendar(name: "MS Boys Soccer White", sport: "Soccer", url: "https://api.veracross.com/oakwood/teams/63334.ics?t=94e62380df52e1b421a352f07a4587d5&uid=8BE4A9AF-0964-47DF-ACF8-B23E9D53608C"),
    TeamCalendar(name: "MS Boys Soccer Green", sport: "Soccer", url: "https://api.veracross.com/oakwood/teams/63335.ics?t=21cb19778b862f274250d88f1f87bd16&uid=CBE3D199-AEBF-4636-AC08-F1D51D5C8DF6"),
    TeamCalendar(name: "Girls MS Soccer", sport: "Soccer", url: "https://api.veracross.com/oakwood/teams/63329.ics?t=b79452fc023799dcd2eb90244b1affce&uid=447681DE-AD75-4818-8F5B-88B657DAAFD3"),

    // Volleyball
    TeamCalendar(name: "Boys Varsity Volleyball", sport: "Volleyball", url: "https://api.veracross.com/oakwood/teams/63362.ics?t=dc18e34114330b5d0c97b432895b4cfc&uid=ECC1EBA8-F92C-4D32-9D5C-B3CD0994386B"),
    TeamCalendar(name: "Boys JV Volleyball", sport: "Volleyball", url: "https://api.veracross.com/oakwood/teams/63355.ics?t=c6af542f06bfc1fb70487fed250c1c31&uid=5DC4935D-291A-4FD7-99AD-FEE5371060D8"),
    TeamCalendar(name: "Girls Varsity Volleyball", sport: "Volleyball", url: "https://api.veracross.com/oakwood/teams/63344.ics?t=56df6da5cd8ae9b7972aab67eb8421e3&uid=42832B98-8F28-40B6-A6DE-04E68C79066F"),
    TeamCalendar(name: "Girls JV Volleyball", sport: "Volleyball", url: "https://api.veracross.com/oakwood/teams/63346.ics?t=77abc72d576971e790feec5428830868&uid=C8714A82-4B2D-4D59-BF2F-D5ED1C07D344"),
    TeamCalendar(name: "Girls Freshmen Volleyball", sport: "Volleyball", url: "https://api.veracross.com/oakwood/teams/64043.ics?t=c31770ab56e17806fe9b19e6b1481475&uid=C0277674-A73C-4D43-B710-B8523D4C9B9E"),
    TeamCalendar(name: "Co-Ed MS Volleyball Green", sport: "Volleyball", url: "https://api.veracross.com/oakwood/teams/63327.ics?t=e52937acde67ac0c635b0e886d218103&uid=274347FF-94F5-456F-85CE-8AF7D9BAA317"),
    TeamCalendar(name: "Co-Ed MS Volleyball White", sport: "Volleyball", url: "https://api.veracross.com/oakwood/teams/63326.ics?t=81a2c60164a6d5778cc3f8eb306b5efc&uid=298AE463-2E0A-43C5-9094-9B0958339F74"),
    TeamCalendar(name: "Girls 8th Grade Volleyball", sport: "Volleyball", url: "https://api.veracross.com/oakwood/teams/63325.ics?t=263a277860153ca87584b6bb1769c244&uid=FC73D5E7-1C30-4704-9351-1141CC72D5B5"),
    TeamCalendar(name: "MS 6th/7th Girls Volleyball Green", sport: "Volleyball", url: "https://api.veracross.com/oakwood/teams/63337.ics?t=1285f7c99eaa53c2351b1f1121adec0a&uid=4E8A7958-AC1E-4883-9EB3-E53BFC6CB5AD"),
    TeamCalendar(name: "MS 6th/7th Girls Volleyball White", sport: "Volleyball", url: "https://api.veracross.com/oakwood/teams/63336.ics?t=d03de2c75681e046d898ce4b97ff69d9&uid=F41034CC-55CD-48CA-8D0F-3CD60E796C25"),

    // Tennis
    TeamCalendar(name: "Boys Varsity Tennis", sport: "Tennis", url: "https://api.veracross.com/oakwood/teams/63360.ics?t=dbb1e81f2865f8124f0deade95343876&uid=8522521D-D017-454B-90E2-677DF2E43328"),
    TeamCalendar(name: "Girls Varsity Tennis", sport: "Tennis", url: "https://api.veracross.com/oakwood/teams/63343.ics?t=aa6eedaac8e3010c7a45006079270160&uid=93BE6668-1910-4F97-9550-F26D5976CD05"),

    // Cross Country & Track
    TeamCalendar(name: "Co-Ed Varsity Cross Country", sport: "Cross Country", url: "https://api.veracross.com/oakwood/teams/63345.ics?t=dafa16dcc29234246794c94bd75121ec&uid=DC351C24-848F-43F4-A2F5-5F6CC35A457B"),
    TeamCalendar(name: "MS Coed Cross Country", sport: "Cross Country", url: "https://api.veracross.com/oakwood/teams/63328.ics?t=dd8d12348ae40f9ef7e08f8bb220a897&uid=26BA5657-2BC6-48D4-B5E5-D89D90152BC5"),
    TeamCalendar(name: "Co-Ed Varsity Track & Field", sport: "Track & Field", url: "https://api.veracross.com/oakwood/teams/63358.ics?t=9c4b7d73ed3a163d84e572f70ab8bc38&uid=D13B9403-7A02-4D06-8DBB-CD73D7E8FA9C"),
    TeamCalendar(name: "CoEd MS Track & Field", sport: "Track & Field", url: "https://api.veracross.com/oakwood/teams/63330.ics?t=d21bf7f03ae201dff0d10d0b1066e970&uid=51335680-A507-4DF5-A2D2-FE8E7A5797AB"),

    // Other Sports
    TeamCalendar(name: "Badminton", sport: "Badminton", url: "https://api.veracross.com/oakwood/teams/63361.ics?t=a895eae7941b2decb9eabe0503b83f04&uid=0B6B9E80-8ECC-4D75-A56B-E26C5A1820F1"),
    TeamCalendar(name: "Co-Ed Varsity Swim", sport: "Swimming", url: "https://api.veracross.com/oakwood/teams/63359.ics?t=25689dbfd35d7d9b683aba171ce0818d&uid=32F2C978-3B1D-41D1-92D9-41B9B0D62EEB"),
    TeamCalendar(name: "HS Co-Ed Golf", sport: "Golf", url: "https://api.veracross.com/oakwood/teams/63357.ics?t=e4032f32627223a5e214b95df20c348e&uid=6FE94299-9468-4A42-8883-FFF31343ABE5"),
    TeamCalendar(name: "HS Varsity Wrestling", sport: "Wrestling", url: "https://api.veracross.com/oakwood/teams/63352.ics?t=d5e32dfa128b7ea85d2df4f37a4419fc&uid=B68990C6-9A75-4EC9-B329-8CC86ECCD792"),
    TeamCalendar(name: "Cheer Team", sport: "Cheer", url: "https://api.veracross.com/oakwood/teams/63351.ics?t=0faed045fef8cf0b2be883e3181d36f2&uid=F5E6B47E-EC34-4CB1-9A79-60373944691A"),
    TeamCalendar(name: "Club Girls Softball", sport: "Softball", url: "https://api.veracross.com/oakwood/teams/63356.ics?t=acc847c5378c6de31f6f21ee95161839&uid=1EF28195-3CFD-401F-88A1-F333666DA17E"),
    TeamCalendar(name: "Varsity Boys Baseball", sport: "Baseball", url: "https://api.veracross.com/oakwood/teams/63967.ics?t=e5ed25758d7774d8e8f41a22e9ceb96d&uid=64EFE2E1-753A-4CCF-A5EF-F8F679E12BCD"),

    // Flag Football
    TeamCalendar(name: "CoEd Flag Football 6th/7th Green", sport: "Flag Football", url: "https://api.veracross.com/oakwood/teams/63324.ics?t=3a0784710dfb8d8ca650779826cfa19d&uid=808516E1-4B7D-4AA5-BEB5-89B9C52E4D2C"),
    TeamCalendar(name: "CoEd Flag Football 6th/7th White", sport: "Flag Football", url: "https://api.veracross.com/oakwood/teams/63339.ics?t=7d0c265b983af97fc14d0167807f4d13&uid=3F847A54-147D-418B-9DC3-0683C107B643"),
    TeamCalendar(name: "Co-Ed 8th Grade Flag Football", sport: "Flag Football", url: "https://api.veracross.com/oakwood/teams/63323.ics?t=193d326e9e66cdd1231897e537f95f2f&uid=2F8AC376-D0EB-4494-8E24-A1DE19C01599"),
]
