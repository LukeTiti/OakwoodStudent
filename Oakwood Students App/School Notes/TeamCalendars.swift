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

let teamCalendars: [TeamCalendar] = [
    // Basketball - Boys
    TeamCalendar(name: "Boys Varsity Basketball", sport: "Basketball", url: "https://api.veracross.com/oakwood/teams/62364.ics?t=574b1058ac7e848e69b5c195b9c6871f&uid=C8955EBA-FBF4-4238-8DDC-0DA396078E59"),
    TeamCalendar(name: "Boys JV Basketball", sport: "Basketball", url: "https://api.veracross.com/oakwood/teams/62363.ics?t=303205835d89ade46088c2300119db66&uid=1D83C67E-9040-4571-80D9-98149C09E69D"),
    TeamCalendar(name: "Boys Frosh Soph Basketball", sport: "Basketball", url: "https://api.veracross.com/oakwood/teams/62367.ics?t=8d80639ac7daddf28ba1022fc1c62d43&uid=BB6D0750-761D-496C-9F66-53202ADA8768"),
    TeamCalendar(name: "6th/7th Boys Basketball Green", sport: "Basketball", url: "https://api.veracross.com/oakwood/teams/63242.ics?t=36aae8274d21f8755a7d38e3c4249900&uid=7985C4FD-E314-4EB2-A10B-FD18F2D311B2"),
    TeamCalendar(name: "6th/7th Boys Basketball White", sport: "Basketball", url: "https://api.veracross.com/oakwood/teams/63243.ics?t=454e358a2cb4605a1505ed552f177c06&uid=9F6AFF60-551E-4ED3-86A0-FC6AB2450296"),
    TeamCalendar(name: "Boys 6th Grade Basketball", sport: "Basketball", url: "https://api.veracross.com/oakwood/teams/62349.ics?t=de6979a535d2fb6ef584ff2b76da567b&uid=44BE0855-1672-4EEC-992F-E807557165F1"),
    TeamCalendar(name: "Boys 7th Grade Basketball", sport: "Basketball", url: "https://api.veracross.com/oakwood/teams/62351.ics?t=1f416c2e41299a4e91e71144bd86906a&uid=A64FC611-41E2-4CBF-A844-7CAC39748BAA"),
    TeamCalendar(name: "Boys 8th Grade Basketball", sport: "Basketball", url: "https://api.veracross.com/oakwood/teams/62356.ics?t=6d306b7db8585e5a9dedec50f247327f&uid=E4C4FE65-57C3-4C15-B9FE-A25A64DCEF20"),

    // Basketball - Girls
    TeamCalendar(name: "Girls Varsity Basketball", sport: "Basketball", url: "https://api.veracross.com/oakwood/teams/62365.ics?t=a645614c28255fd1a77cd49d2583fa2e&uid=774F3AF9-254C-4F21-A394-C7065E4CB9DD"),
    TeamCalendar(name: "Girls MS Basketball", sport: "Basketball", url: "https://api.veracross.com/oakwood/teams/62350.ics?t=0fb4aa784f5ce136fad43d1098aacb02&uid=35BBC154-5E77-4B89-97EA-72CADCE71393"),

    // Soccer
    TeamCalendar(name: "Boys Varsity Soccer", sport: "Soccer", url: "https://api.veracross.com/oakwood/teams/62362.ics?t=a1757d1cd7a28ef06d1d408ee3462218&uid=7E91D6AA-9ADF-41D5-8758-07668A2CA838"),
    TeamCalendar(name: "Girls Varsity Soccer", sport: "Soccer", url: "https://api.veracross.com/oakwood/teams/63128.ics?t=5d3d25ec32b8375ee747bd426220f903&uid=C359A745-A526-4CB7-A094-70918C91617E"),
    TeamCalendar(name: "MS Boys Soccer White", sport: "Soccer", url: "https://api.veracross.com/oakwood/teams/62352.ics?t=b7818f919d335ed73d60efca6326168d&uid=812D8989-2FD3-4C53-8C44-9AF44B0C550F"),
    TeamCalendar(name: "MS Boys Soccer Green", sport: "Soccer", url: "https://api.veracross.com/oakwood/teams/62353.ics?t=a3f3c1e4cf661f0a054c76e2fcf74a4e&uid=FE193F94-ADB0-44A3-9ABA-2B3168FB7D9D"),
    TeamCalendar(name: "Girls MS Soccer", sport: "Soccer", url: "https://api.veracross.com/oakwood/teams/62347.ics?t=f8586f6f6033b90c11c0eb7498661649&uid=1B80CC30-24A6-4CFA-A6B6-2A4920B13AE1"),

    // Volleyball
    TeamCalendar(name: "Boys Varsity Volleyball", sport: "Volleyball", url: "https://api.veracross.com/oakwood/teams/62376.ics?t=4a66d55576d26489cb6dec8a3356876a&uid=17FF6E41-7CE0-4E4B-9831-4F0075B51309"),
    TeamCalendar(name: "Boys JV Volleyball", sport: "Volleyball", url: "https://api.veracross.com/oakwood/teams/62369.ics?t=dc9b109f9d931f1242dd122a517b1498&uid=0853106B-6D69-44A6-B183-5D21B4462DDD"),
    TeamCalendar(name: "Girls Varsity Volleyball", sport: "Volleyball", url: "https://api.veracross.com/oakwood/teams/62359.ics?t=dca5673ca6fd59aab1c8b09bcc57825a&uid=B7AE3484-21AC-4529-B895-A9613813333D"),
    TeamCalendar(name: "Girls JV Volleyball", sport: "Volleyball", url: "https://api.veracross.com/oakwood/teams/62361.ics?t=bcb7be5017fefc38436b71199a2896dc&uid=88FEA4F6-ED8E-454D-8E57-4D06AF27905D"),
    TeamCalendar(name: "Co-Ed MS Volleyball Green", sport: "Volleyball", url: "https://api.veracross.com/oakwood/teams/62345.ics?t=819d264538c46722e8cd6fd4c8ed650a&uid=DC184533-C72C-4A35-A5EF-5ACB6474D625"),
    TeamCalendar(name: "Co-Ed MS Volleyball White", sport: "Volleyball", url: "https://api.veracross.com/oakwood/teams/62344.ics?t=6b09e4eb459bd56e76bb5375218f0fcf&uid=C946DB40-958C-44E0-A6C9-CDA7F1FBDED1"),
    TeamCalendar(name: "Girls 8th Grade Volleyball", sport: "Volleyball", url: "https://api.veracross.com/oakwood/teams/62343.ics?t=1157a8f68aebbc0cbf1a366c56775840&uid=CA5913D0-038D-460A-B415-AEB1FC3003CD"),
    TeamCalendar(name: "MS 6th/7th Girls Volleyball Green", sport: "Volleyball", url: "https://api.veracross.com/oakwood/teams/62355.ics?t=c3ade2b0b1f64ecf917c699f1060e553&uid=3CC63E31-F98B-4ABF-B57F-CB5545075654"),
    TeamCalendar(name: "MS 6th/7th Girls Volleyball White", sport: "Volleyball", url: "https://api.veracross.com/oakwood/teams/62354.ics?t=2184afec7666f1cd4cb7725ff8a6429d&uid=BC42B07A-08E2-4229-9493-ADBB16251FCF"),

    // Tennis
    TeamCalendar(name: "Boys Varsity Tennis", sport: "Tennis", url: "https://api.veracross.com/oakwood/teams/62374.ics?t=53390f1301786d506303bdc44e302d7f&uid=7DB6913A-62A9-4D52-9228-4260778AE64E"),
    TeamCalendar(name: "Girls Varsity Tennis", sport: "Tennis", url: "https://api.veracross.com/oakwood/teams/62358.ics?t=194864848167ed9426c8a302eb8db14e&uid=AB61F612-5562-4A86-8BEC-8894A1EAF411"),

    // Cross Country & Track
    TeamCalendar(name: "Co-Ed Varsity Cross Country", sport: "Cross Country", url: "https://api.veracross.com/oakwood/teams/62360.ics?t=a8e16d09d9126467ec786c2189254802&uid=44FF1A51-0CFE-4341-B79A-71BF96721EE4"),
    TeamCalendar(name: "MS Coed Cross Country", sport: "Cross Country", url: "https://api.veracross.com/oakwood/teams/62346.ics?t=047965765ed62eb4a088ecafdd40a7cd&uid=D2968A4F-04E9-49FB-B48B-8FAD5BF06591"),
    TeamCalendar(name: "Co-Ed Varsity Track & Field", sport: "Track & Field", url: "https://api.veracross.com/oakwood/teams/62372.ics?t=0a0f9a8a5952686e6d8a51b686fb6ad1&uid=14715B94-0B76-41B7-888D-91266D6F7A90"),
    TeamCalendar(name: "CoEd MS Track & Field", sport: "Track & Field", url: "https://api.veracross.com/oakwood/teams/62348.ics?t=318c7bf91d7931cb462b32f139771f3e&uid=A90A4C5C-8351-49AC-A5C3-436BE97FC7F6"),

    // Other Sports
    TeamCalendar(name: "Badminton", sport: "Badminton", url: "https://api.veracross.com/oakwood/teams/62375.ics?t=ceb6b7d5c026f4a6a2158fd5b5f8281e&uid=2EF8C1CC-2386-4F2F-86A3-7CA78D032314"),
    TeamCalendar(name: "Co-Ed Varsity Swim", sport: "Swimming", url: "https://api.veracross.com/oakwood/teams/62373.ics?t=a6d7cac2ea24388059904f3b40faf0f9&uid=AAC96E6C-4117-4660-8752-851C48BC473A"),
    TeamCalendar(name: "HS Co-Ed Golf", sport: "Golf", url: "https://api.veracross.com/oakwood/teams/62371.ics?t=b1fd97d6a190a87ebf943d197bba18e1&uid=F225EE59-AAB5-4107-A5B8-54DC80B83507"),
    TeamCalendar(name: "HS Varsity Wrestling", sport: "Wrestling", url: "https://api.veracross.com/oakwood/teams/62368.ics?t=48c2ed9e45a3e21240b57d313fb56c61&uid=1662A887-3FFC-4A6E-ABC9-515EAFED46D0"),
    TeamCalendar(name: "Cheer Team", sport: "Cheer", url: "https://api.veracross.com/oakwood/teams/62366.ics?t=b3b0583a078f2178a08668d3650f2b63&uid=435AF1EB-641C-4C34-9738-F104E30A0061"),
    TeamCalendar(name: "Club Girls Softball", sport: "Softball", url: "https://api.veracross.com/oakwood/teams/62370.ics?t=bfd59280efc758e2d47700d0cdd1c087&uid=C2095B6D-5523-4710-AFB2-4377711BA8E1"),

    // Flag Football
    TeamCalendar(name: "CoEd Flag Football 6th/7th Green", sport: "Flag Football", url: "https://api.veracross.com/oakwood/teams/62342.ics?t=cff17b0cfc730d086aa5b22ad9fcacf9&uid=6DEE03D8-7E92-4449-AF0F-8175FC1DF71F"),
    TeamCalendar(name: "CoEd Flag Football 6th/7th White", sport: "Flag Football", url: "https://api.veracross.com/oakwood/teams/62357.ics?t=fe95faa7044fec43466e8316a02ac258&uid=3BE0C9FD-CD49-4DC6-8197-F9B6217F8993"),
    TeamCalendar(name: "Co-Ed 8th Grade Flag Football", sport: "Flag Football", url: "https://api.veracross.com/oakwood/teams/62341.ics?t=6c05117806569ee6edc920ebbc4c6a20&uid=685D5111-F3F2-4D8B-81AE-A10F72C4CB61"),
]
