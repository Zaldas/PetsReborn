-- data/jugPets.lua
-- Jug pet name → duration in minutes.
-- Used by data.lua to build jugPetNames (bool) and jugPetDurations (seconds) in data.init().
-- HorizonXI-specific pets without confirmed data default to 60.
-- Add new HorizonXI pets here; do NOT edit data.lua for pet additions.
return {
    -- 30 minute pets
    CrabFamiliar    = 30,
    CourierCarrie   = 30,
    AmigoSabotender = 30,

    -- 60 minute pets
    SheepFamiliar    = 60,
    FlowerpotBill    = 60,
    TigerFamiliar    = 60,
    FlytrapFamiliar  = 60,
    LizardFamiliar   = 60,
    MayflyFamiliar   = 60,
    EftFamiliar      = 60,
    BeetleFamiliar   = 60,
    AntlionFamiliar  = 60,
    MiteFamiliar     = 60,
    LullabyMelodia   = 60,
    FlowerpotBen     = 60,
    SaberSiravarde   = 60,
    FunguarFamiliar  = 60,
    ShellbusterOrob  = 60,
    ColdbloodComo    = 60,
    Homunculus       = 60,
    VoraciousAudrey  = 60,
    AmbusherAllie    = 60,
    PanzerGalahad    = 60,
    LifedrinkerLars  = 60,
    ChopsueyChucky   = 60,

    -- 90 minute pets
    HareFamiliar   = 90,
    KeenearedSteffi = 90,
    GooeyGerard    = 90,
    CrudeRaphie    = 90,

    -- 120 minute pets
    NurseryNazuna    = 120,
    CraftyClyvonne   = 120,
    PrestoJulio      = 120,
    SwiftSieghard    = 120,
    MailbusterCetas  = 120,
    AudaciousAnna    = 120,
    TurbidToloi      = 120,
    LuckyLulush      = 120,
    DipperYuly       = 120,
    ['Dapper Mac']   = 120,  -- in-game name has space
    DapperMac        = 120,  -- alternate (no space)
    DiscreetLouise   = 120,
    FatsoFargann     = 120,
    FaithfulFalcorr  = 120,
    BugeyedBroncha   = 120,
    BloodclawShashra = 120,
    BloodclawShasra  = 120,  -- alternate spelling; both kept, reported client string varies
    GorefangHobs     = 120,
    DroopyDortwin    = 120,
    SunburstMalfik   = 120,
    WarlikePatrick   = 120,
    ScissorgaleXerin = 120,
    ScissorlegXerin  = 120,  -- alternate spelling; both kept, reported client string varies
    RhymingShizuna   = 120,
    AttentiveIbuki   = 120,
    AmiableRoche     = 120,
    BrainyWaluis     = 120,
    HeraldHenry      = 120,
    SuspiciousAlice  = 120,
    HeadbreakerKen   = 120,
    RedolentCandi    = 120,
    AnklebiterJedd   = 120,
    CaringKiyomaro   = 120,
    HurlerPercival   = 120,
    BlackbeardRandy  = 120,
    FleetReinhard    = 120,
    AlluringHoney    = 120,
    BouncingBertha   = 120,
    BraveHeroGlenn   = 120,
    CursedAnnabelle  = 120,
    GenerousArthur   = 120,
    SharpwitHermes   = 120,
    SwoopingZhivago  = 120,
    ThreestarLynn    = 120,
    PonderingPeter   = 120,
    SlipperySimon    = 120,
    ['Left-HandedYoko']  = 120,
    SultryPatrice    = 120,
    MischievousMichael   = 120,
    ChoralLeera      = 120,
    CraftyCalpisci   = 120,
    VivaciousVickie  = 120,

    -- 180 minute pets
    ['Flowerpot Merle'] = 180,  -- in-game name has space
    FlowerpotMerle      = 180,  -- alternate (no space)

    -- HorizonXI-specific pets — duration unconfirmed, defaulting to 60
    MosquitoFamiliar = 60,
    SpiderFamiliar   = 60,
    GustyGerald      = 60,
    AcuexFamiliar    = 60,
    FluffyBredo      = 60,
    CopiousAndrew    = 60,
    SharpEarRopipi   = 60,
    AudaliciousGully = 60,
    ['Aged Angus']   = 60,
    AgedAngus        = 60,
    SweetCaroline    = 60,
}
