#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-only
"""Verify opening gameplay using original Shockwave fixtures and native inputs.

Fixtures and screenshots stay in the chosen output directories, outside the app.
This checks the listed interactions, not all levels or server-dependent features.
"""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess
import urllib.request
import zipfile

FIXTURES = [{'name': 'Backlot.zip', 'url': 'https://archive.org/download/legostudiosbacklot/LEGO%20Studios%20Backlot.zip', 'sha256': 'c2473b1363753d9be8b78c8622c5d0f7dfb71cb14a9be983bcc09ae1b0ed9516'}, {'name': 'Hasbro.zip', 'url': 'https://archive.org/download/hasbrointeractive/Hasbro%20Interactive%20Shockwave%20Games.zip', 'sha256': '2d22644d29824105ac546f2b2c75d36d77b520f01069c41304768cca97a26a40'}, {'name': 'CreepyPong.zip', 'url': 'https://archive.org/download/miniclip_shockwave-games/Miniclip%20Shockwave%20Player%20Games/Creepy%20Pong%20-%20Silent%20Bay%20Studios.zip', 'sha256': 'ef234de6ab12280e8baeb41e5b8a05193cc3839dcb6d3019878192589acae77f'}, {'name': 'MonsterBash.zip', 'url': 'https://archive.org/download/miniclip_shockwave-games/Miniclip%20Shockwave%20Player%20Games/MONSTER%20BASH.zip', 'sha256': 'b6b83c7a81f721236ecde807b021fcfe7da8987bb57bb9d4ecfea5cdf7756cdc'}, {'name': 'Junkbot.zip', 'url': 'https://archive.org/download/legojunkbot/Junkbot.zip', 'referer': '', 'sha256': 'b45c519d7a4dd03708b960439cd0d87889a3fb18b3e6b1b101c4befbeb8f7b81'}, {'name': 'WorldBuilder.zip', 'url': 'https://archive.org/download/lego-world-builder/Lego%20WorldBuilder.zip', 'referer': '', 'sha256': '96a21af4d0de38a34b94d7cb2ee21b34908a58d3f0ca36d01fdb9acf13655d67'}, {'name': 'Merlin2.dcr', 'url': 'https://themetalbox.com/dcr/games/merlin_2.dcr', 'referer': 'https://themetalbox.com/index.php?page=merlin_2', 'sha256': '991eeae0326307f5846a5711c6aa98ce45aca75811d4e299b580a1cd77a5f630'}, {'name': 'BreakoutLite.dcr', 'url': 'https://themetalbox.com/dcr/games/breakout_lite.dcr', 'referer': 'https://themetalbox.com/index.php?page=breakout_lite', 'sha256': 'ebb2f1f59d3bbc9a940c0de62cb9ff4695ccc5f1399a86bebe790a28ceda7e1a'}]

FIXTURES.extend([{'name': 'Courage/game.dcr', 'url': 'https://archive.org/download/courage-in-creepy-tv/game.dcr', 'sha256': '61e6cc9a74cf0887d3c5691339ff414d278bfbe7e1e0dea16b4749bcce6a85d8'}, {'name': 'MiniGolf/nwmgmain.dcr', 'url': 'https://archive.org/download/nwmgholes/nwmgmain.dcr', 'sha256': '893caea123c1aa8cfd8a5ea62c0d82e9c35e3ca3cbd5e1fa5a3834877ef386ab'}, {'name': 'MiniGolf/nwmgholes.cct', 'url': 'https://archive.org/download/nwmgholes/nwmgholes.cct', 'sha256': 'e2680fab2bac5bb763d620736f1ccd216c855919ab2f2858e5d955f99156acad'}])
FIXTURES.extend([
    dict(name='AirShow.zip', url='https://archive.org/download/miniclip_shockwave-games/Miniclip%20Shockwave%20Player%20Games/Air%20Show%20-%20Silent%20Bay%20Studios.zip', sha256='cc078c81159de68137f73b4901dbf2736a19c36ec77a5259d8596dfa8654293d'),
    dict(name='Nintendo.zip', url='https://archive.org/download/nintendo-shockwave-webgames/Nintendo%20Shockwave%20Webgames.zip', sha256='95fc4866b3c77e8d3310b1eae91c75776d47be148198d4c33bc3050b30b92c7e'),
    dict(name='Eidos.zip', url='https://archive.org/download/eidos-shockwave-webgames/Eidos%20Shockwave%20Webgames.zip', sha256='9cb4b9a5da9b7e95b3217fabc3e25c32f33adee6df3e6d35273fd0bc0dadbce5'),
])

FIXTURES.extend([
    dict(name='BeachSoccer.zip', url='https://archive.org/download/miniclip_shockwave-games/Miniclip%20Shockwave%20Player%20Games/Beach%20Soccer%20-%20Silent%20Bay%20Studios.zip',
         sha256='82e8825f77dc79b26d240218a369f73c5e2a0f3c906a1905015aa96942bd5f52'),
    dict(name='AmericanFootball.zip', url='https://archive.org/download/miniclip_shockwave-games/Miniclip%20Shockwave%20Player%20Games/American%20Football%20-%20Silent%20Bay%20Studios.zip',
         sha256='dba8b6d9c5a551d92ce90e61b583f181df0c0e85d922ea39b6a888ab0d3b4b99'),
    dict(name='FreeRunning.zip', url='https://archive.org/download/miniclip_shockwave-games/Miniclip%20Shockwave%20Player%20Games/Free%20Running%20-%20Silent%20Bay%20Studios.zip',
         sha256='3d37a257c9f98e59c3fab438919a1bfd9f0c6de1ecf5846cc584185d711876f9'),
])

FIXTURES.extend(json.loads(Path(__file__).with_name('shockwave-galidor-fixtures.json').read_text()))

def click(x, y, wait=2): return dict(click=[x, y], wait=wait)
def key(value, code, hold=1, wait=1): return dict(key=value, keyCode=code, hold=hold, wait=wait)
def condition(check):
    # Evaluate read-only scalar expressions; compare them in JavaScript. Lingo
    # command parsing can interpret a top-level equality as an assignment.
    return "(async()=>{async function value(code){const g=JSON.parse(__vm.mcp_get_globals()).globals;if(g[code])return g[code].value;const r=JSON.parse(await __vm.mcp_eval_lingo(code));if(!r.success)throw Error(r.error);return r.result_value;}return " + check + ";})()"

def inspect(expressions):
    return "(async()=>{const out={};for(const code of " + json.dumps(expressions) + "){const r=JSON.parse(await __vm.mcp_eval_lingo(code));const inspected=r.datum_id?JSON.parse(__vm.mcp_inspect_datum(r.datum_id)):null;out[code]=inspected&&!inspected.error?inspected:r;}return out;})()"

# Inputs follow each original game's menus. Assertions require game state or
# input-driven progress, rather than treating a loaded title screen as success.
CASES = [
    dict(name='Galidor', source='Galidor', entry='galidorgame.dcr', wait=10,
         # Archived placeholder cast and obsolete save service; retained in the evidence.
         expectedMissing=['dummy.cct','game.asp'],
         steps=[click(281,406,8),click(65,145,.5),click(175,93,.5),click(65,145,.5),
                click(270,93,.5),click(65,145,.5),
                dict(click=[555,390],wait=10,
                     expect=condition("Number(await value('gGame.getPlayerZoneElement().ctrl.getCoord().x')) === -142 && Number(await value('gGame.getPlayerZoneElement().ctrl.getCoord().y')) === 278")),
                dict(drag=[330,355,350,355],wait=.1),
                dict(key='v',keyCode=9,hold=.2,wait=.05,
                     expect=condition("Number(await value('gGame.getPlayerZoneElement().ctrl.getCoord().z')) > 0 && await value('gGame.getPlayerZoneElement().ctrl.getModel().getFlashLabel()') === '\"jump\"'"))],
         expect=condition("Number(await value('gGame.getPlayerZoneElement().ctrl.getCoord().x')) > -142 && Number(await value('gGame.pRealm.actionZone.getElementsByType(#entrance).count')) === 3 && await value('sprite(gGame.getPlayerZoneElement().ctrl.getView().spr).getFlashProperty(\"_level0/head/siktari\",#visible)') === '\"true\"'")),
    dict(name='GreatFireworkRace', source='Eidos.zip', entry='Games/Great Firework Race.dcr',
         steps=[click(433,298,4),dict(modifier='shift',hold=1.5,wait=.1)],
         expect=condition("JSON.parse(__vm.mcp_get_execution_state()).current_frame === 5 && Number(await value('velocity')) > 0")),
    dict(name='AirShow', source='AirShow.zip', entry='projector-loader.dcr', wait=16,
         projector=dict(member='air-show.exe', offset=9275434, size=7739,
                        sha256='746e435033d5b894aad1863b7b118d7a973734968dc265032f9ada6646927717'),
         # Ten seconds and a bare click were enough on an idle machine. Under
         # load this title reaches its title screen — game object built, audio
         # playing — but the press lands before the button answers, so it sits
         # there. Its siblings in this engine all wait sixteen and roll over
         # first; the recorded scope below is unchanged.
         steps=[dict(click=[460,316],hover=.8,wait=2),click(467,135,10),key(' ',49,.4,2),key(' ',49,.4,3),key('\uf703',124,.6,.1)],
         expect=condition("Number(await value('gGame.pPlayerTimeRemaining')) < 60000 && Number(await value('gGame.pPlayerTimeRemaining')) > 0 && await value('gGame.pPlayer.pOldPos.x') !== await value('gGame.pPlayer.pStartPos.x')")),
    dict(name='BarrelMaze', source='Nintendo.zip', entry='Games/Donkey Kong Country Barrel Maze/dkbmload.dcr', wait=8,
         parameters={'sw1':'./','sw2':'Copyright2003Skyworks'},
         # Allow a rollover frame before pressing the bitmap button.
         steps=[dict(click=[35,267],hover=.5,wait=2),key('\uf703',124,.25,.1)],
         expect=condition("await value('state') === '#play' && Number(await value('playerX')) > 112")),
    dict(name='Courage', source='Courage', entry='game.dcr', wait=10,
         steps=[key(' ',49,.2,3),key(' ',49,.2,1),key(' ',49,.2,1),click(126,286),
                key(' ',49,.2,.6),key(' ',49,.2,.6),key(' ',49,.2,2),key(' ',49,.2,.7),
                key('\uf700',126,1,.2),key('\uf702',123,1.1,.4)] + [key(' ',49,.2,.8)]*3 +
               [key(' ',49,.2,.8),key(' ',49,.2,.8),key(' ',49,.2,2),key(' ',49,.2,.6),
                key('\uf703',124,.65,.3),key(' ',49,.2,1)],
         expect=condition("await value('obw.rpgMoto.hero.inventoryExists(#dogfood)') === '1' && await value('obw.rpgMoto.hero.inventoryExists(#can_opener)') === '1' && await value('obw.rpgMoto.currentRoom.info.name') === '#kitchen' && await value('obw.rpgMoto.currentRoom.row[1].col[1].gfx.name') === '\"001\"' && await value('obw.rpgMoto.blitter.renderProps.roomBuffer.image.getPixel(152,104)') === 'rgb(139, 80, 0)'")),
    dict(name='MiniGolf', source='MiniGolf', entry='nwmgmain.dcr',
         parameters={'sw1':'./','sw2':'Copyright2000NabiscoInc'},
         steps=[click(153,157),click(205,195)],
         expect=condition("await value('gamePlayMode') === '#Practice' && Number(await value('readhackv(holeStrokes[1])')) > 0")),
    dict(name='Merlin2', source='Merlin2.dcr', entry='Merlin2.dcr',
         parameters={'sw1':'#metal','sw2':'','sw3':'','bgcolor':'#000000'},
         page='https://themetalbox.com/index.php?page=merlin_2',
         steps=[click(320,188),click(320,219,.5),key('\uf703',124,1,.1)],
         expect=condition("(await value('g.merlinMain.pMode')).toLowerCase() === '#game'")),
    dict(name='BreakoutLite', source='BreakoutLite.dcr', entry='BreakoutLite.dcr',
         steps=[click(320,360),click(480,360)],
         expect=condition("await value('game.doing') === '1' && Number(await value('brickmaster.brickcounter')) < 128")),
    dict(name='Centipede', source='Hasbro.zip', entry='Games/centipede.dcr',
         # Mushroom placement varies; allow time for multiple shots to score.
         steps=[click(160,145),key(' ',49,6,.1)],
         expect=condition("Number(await value('gPoints')) > 0 && JSON.parse(__vm.mcp_get_execution_state()).current_frame === 4")),
    dict(name='Frogger', source='Hasbro.zip', entry='Games/frogger.dcr',
         steps=[click(112,180),key('\uf700',126)],
         expect=condition("Number(await value('gPoints')) > 0 && await value('gDoneGame') === '0' && JSON.parse(__vm.mcp_get_execution_state()).current_frame === 10")),
    dict(name='MissileCommand', source='Hasbro.zip', entry='Games/missilecommand.dcr',
         steps=[click(128,140),click(80,245,3),click(60,80),click(170,90)],
         expect=condition("await value('gameactive') === '1'")),
    dict(name='SuperBreakout', source='Hasbro.zip', entry='Games/superbreakout.dcr',
         steps=[click(110,139),click(160,230),click(70,230)],
         expect=condition("await value('gGameType') === '\"double\"' && Number(await value('gCurrentPlayer.pBallNumber')) > 1")),
    dict(name='Junkbot', source='Junkbot.zip', entry='junkbot2_13g_asp.dcr',
         steps=[click(553,378,5),click(553,378),click(195,168),click(195,168),
                click(225,340),click(225,340),click(210,99),click(210,99),
                dict(drag=[350,350,410,350],wait=2),click(350,350,1),click(410,350)],
         expect=condition("await value('glob.PLAYER.play_manager.activeState') === '#Run' && Number(await value('glob.PLAYER.play_manager.gamestatus.moves')) > 0")),
    dict(name='WorldBuilder', source='WorldBuilder.zip', entry='worldbuilder/worldbuilder.dcr',
         steps=[click(535,120),click(123,275),click(226,339)]+[click(489,195,1)]*5,
         expect=condition("await value('glob.tutorial_manager.pStepName') === '#stepC'")),
    dict(name='Backlot', source='Backlot.zip', entry='LegoStudios.dcr', limited=True,
         steps=[dict(read=inspect(['gMainManager.pSystemManager','gMainManager.pDownloadManager','gMainManager.pGameManager']),wait=0)]),
    dict(name='CreepyPong', source='CreepyPong.zip', entry='projector-loader.dcr', wait=12,
         projector=dict(member='creepy-pong.exe', offset=9275434, size=7344,
                        sha256='6d9041916d5651721d051eec07297e449ae06a4143111c83fbcaba99ea6e94c1'),
         steps=[click(500,260,1),click(350,170,1),click(70,320,15),click(300,350,2),
                dict(drag=[300,350,300,220],wait=2)],
         expect=condition("JSON.parse(__vm.mcp_get_execution_state()).current_frame === 45 && Number(await value('gGame.pTeams[1].pControllingPlayer.pLastShootTime')) > 0 && Number(await value('gGame.pTeams[1].pControllingPlayer.getPosition().x')) > 0")),
    dict(name='MonsterBash', source='MonsterBash.zip', entry='en/monster.dcr', wait=9,
         steps=[click(200,220,1),key(' ',49,0.2,3),key(' ',49,0.2,3),
                key(' ',49,0.2,1.4),key(' ',49,0.2,2),
                dict(read="JSON.parse(__vm.mcp_inspect_3d_model(2,1,'monster'))",wait=0)],
         expect=condition("Number(await value('myNumWhacks')) > 0 && await value('doGameCam') === '1'")),
    # Two more titles from the same Miniclip/Silent Bay engine as Air Show and
    # Creepy Pong. Both need their whole preloader before the title screen's
    # PLAY button answers a click — eight seconds leaves them on a black frame,
    # which is what the launch survey recorded for them. Each condition asks for
    # a live match AND for the ball to have moved through the player's own
    # input; before the menu clicks every one of these game properties is VOID,
    # so a title screen cannot satisfy it. Neither claims a completed match.
    # The `read` step stores the ball's position for the movement comparison and
    # writes nothing back into the movie.
    dict(name='BeachSoccer', source='BeachSoccer.zip', entry='projector-loader.dcr', wait=16,
         projector=dict(member='beach-soccer.exe', offset=10307050, size=7770,
                        sha256='662e8780060a4940495307f9fbdacf069a4e9970f943cfc78abad6bdb5264295'),
         steps=[click(304,354,5),key(' ',49,.2,3),key('z',6,.2,1.5),
                dict(read="(async()=>{const r=JSON.parse(await __vm.mcp_eval_lingo('gGame.pBall.getPosition().x'));return window.__beachSoccerBallX=Number(r.result_value);})()",wait=0),
                # The ball waits on the centre spot until the player kicks off,
                # so its position only leaves that spot through this input.
                key('x',7,.4,2),key('\uf700',126,1.2,.8),key('x',7,.6,2)],
         expect=condition("Number(await value('gGame.pTeams.count')) === 2 && Number(await value('gGame.pRoundMatch')) === 1 && Math.abs(Number(await value('gGame.pBall.getPosition().x'))) < Number(await value('gGame.pFieldWidth')) && Number(await value('gGame.pBall.getPosition().x')) !== window.__beachSoccerBallX")),
    dict(name='AmericanFootball', source='AmericanFootball.zip', entry='projector-loader.dcr', wait=16,
         projector=dict(member='american-football.exe', offset=10307050, size=7775,
                        sha256='ca1ff36bf1d62f26bcf52cc7492bee4c6c5425f9a20542e69808aab5568f3e4c'),
         # Both menu buttons need a rollover frame before the press registers.
         steps=[dict(click=[293,297],hover=.8,wait=5),dict(click=[486,410],hover=.8,wait=6),
                click(294,330,4),
                dict(read="(async()=>{const r=JSON.parse(await __vm.mcp_eval_lingo('gGame.pBall.getPosition().x'));return window.__americanFootballBallX=Number(r.result_value);})()",wait=0),
                key(' ',49,.4,2.5)],
         expect=condition("Number(await value('gGame.pTeams.count')) === 2 && await value('gGame.pPlayerTeamId') === '#team1' && Math.abs(Number(await value('gGame.pBall.getPosition().x')) - window.__americanFootballBallX) > 20")),
    # Found by probe-shockwave-menus.py, not by hand: its record said "gGame is
    # not initialized" and it initializes fine once the preloader is allowed to
    # finish. The up arrow moves the character roughly two thousand units along
    # the roof, which is what the condition checks — the level loading on its
    # own does not satisfy it.
    dict(name='FreeRunning', source='FreeRunning.zip', entry='projector-loader.dcr', wait=16,
         projector=dict(member='free-running.exe', offset=10307050, size=7378,
                        sha256='d3ac3ba9bdd8d123502712c9ec9b41769fb95fbd90ddaa0ffdb0c7317514a196'),
         # The level needs a moment after it opens before it takes input; the
         # stash step's own wait provides it.
         steps=[dict(click=[295,300],hover=.8,wait=8),
                dict(read="(async()=>{const r=JSON.parse(await __vm.mcp_eval_lingo('gGame.pPc.pLastGroundPos.y'));return window.__freeRunningGroundY=Number(r.result_value);})()",wait=3),
                key('\uf700',126,2.0,1.0)],
         expect=condition("Number(await value('gGame.pLevelId')) === 1 && Number(await value('gGame.pPlayerTimeRemaining')) > 0 && Math.abs(Number(await value('gGame.pPc.pLastGroundPos.y')) - window.__freeRunningGroundY) > 100")),
]


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('output',type=Path)
    parser.add_argument('--app',type=Path,default=Path(__file__).resolve().parent.parent/'Flashback.app')
    parser.add_argument('--fixtures',type=Path)
    parser.add_argument('--games',nargs='+',choices=[x['name'] for x in CASES])
    parser.add_argument('--baseline',action='store_true',help='Record failures without requiring the improved compatibility level')
    args=parser.parse_args()
    root=args.output.absolute();root.mkdir(parents=True,exist_ok=False)
    runtime = args.app.resolve()/'Contents/Resources/Shockwave/dirplayer-polyfill.js'
    (root/'Runtime.json').write_text(json.dumps({'app':str(args.app.resolve()),
        'polyfill_sha256':hashlib.sha256(runtime.read_bytes()).hexdigest()},indent=2)+'\n')
    fixtures=(args.fixtures or root/'Fixtures').resolve();fixtures.mkdir(parents=True,exist_ok=True)
    cases=[x for x in CASES if not args.games or x['name'] in args.games]
    for record in FIXTURES:
        if not any(x['source']==record['name'] or record['name'].startswith(x['source']+'/') for x in cases):continue
        target=fixtures/record['name']
        if not target.exists():
            target.parent.mkdir(parents=True,exist_ok=True)
            request=urllib.request.Request(record['url'],headers={'Referer':record.get('referer',record['url'])})
            with urllib.request.urlopen(request,timeout=90) as response:target.write_bytes(response.read())
        assert hashlib.sha256(target.read_bytes()).hexdigest()==record['sha256'],target
    results=[]
    for case in cases:
        out=root/case['name'];out.mkdir()
        source=fixtures/case['source']
        if launcher := case.get('projector'):
            with zipfile.ZipFile(fixtures/case['source']) as archive:
                data=archive.read(launcher['member'])
            movie=data[launcher['offset']:launcher['offset']+launcher['size']]
            assert hashlib.sha256(movie).hexdigest()==launcher['sha256']
        options={k:v for k,v in case.items() if k in ('steps','expect','expectedMissing','parameters','page','wait')}
        (out/'Probe.json').write_text(json.dumps(options,indent=2))
        with (out/'Console.txt').open('w') as log:
            try:
                subprocess.run([str(args.app.resolve()/'Contents/MacOS/Flashback'),'--shockwave-probe',
                                str(source),case['entry'],str(out)],stdout=log,stderr=subprocess.STDOUT,timeout=90)
                detail=(out/'Result.txt').read_text().strip() if (out/'Result.txt').exists() else 'No result'
            except subprocess.TimeoutExpired:detail='Timed out'
        status='PASS' if detail.startswith('PASS:') else 'LIMITED' if case.get('limited') else 'FAIL'
        results.append(dict(game=case['name'],status=status,detail=detail))
        print(case['name']+': '+status+' — '+detail,flush=True)
    (root/'Results.json').write_text(json.dumps(results,indent=2)+'\n')
    passed=sum(x['status']=='PASS' for x in results)
    print(f'{passed}/{len(results)} fixtures passed their recorded opening-gameplay condition.',flush=True)
    if not args.baseline and any(x['status']=='FAIL' for x in results):raise SystemExit(1)

if __name__=='__main__':main()
