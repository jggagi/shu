"""Original vector sketches for the D01 composition; standard library only."""
from pathlib import Path
import random

OUT = Path(__file__).resolve().parents[1] / 'assets' / 'art'

def svg(name, width, height, body):
    OUT.mkdir(parents=True, exist_ok=True)
    (OUT / name).write_text(f'<svg xmlns="http://www.w3.org/2000/svg" width="{width}" height="{height}" viewBox="0 0 {width} {height}">{body}</svg>\n', encoding='utf-8', newline='\n')

def paper():
    rng = random.Random(17)
    body = ['<rect width="1440" height="900" fill="#eee6d6"/>']
    for _ in range(1300):
        x, y = rng.randrange(1440), rng.randrange(900)
        length = rng.randrange(2, 14)
        body.append(f'<path d="M{x} {y}l{length} 1" stroke="#9f967e" stroke-width="0.4" opacity="0.13"/>')
    svg('paper.svg', 1440, 900, ''.join(body))

def courtyard():
    body = '''
    <defs>
      <linearGradient id="sky" x2="0" y2="1"><stop stop-color="#e9eddf"/><stop offset="1" stop-color="#f4eedc"/></linearGradient>
      <linearGradient id="floor" x2="0" y2="1"><stop stop-color="#dbdec7"/><stop offset="1" stop-color="#e9dfc8"/></linearGradient>
      <linearGradient id="roof" x2="0" y2="1"><stop stop-color="#5e776c"/><stop offset="1" stop-color="#899a7f"/></linearGradient>
    </defs>
    <rect width="924" height="498" fill="url(#sky)"/>
    <circle cx="674" cy="87" r="44" fill="#f2e2b8" opacity="0.75"/>
    <path d="M0 232L51 146 115 203 170 94 216 147 269 76 321 172 371 145 419 210 467 99 510 57 575 175 612 135 678 230 754 134 806 209 877 120 924 204V324H0Z" fill="#b2c5b4" opacity="0.46"/>
    <path d="M0 250L67 212 138 142 214 231 279 178 334 260 407 202 487 249 565 149 636 210 704 197 766 274 854 182 924 231V333H0Z" fill="#8fa996" opacity="0.34"/>
    <path d="M0 300Q126 247 214 285T470 266T731 289T924 263V366H0Z" fill="#9dac8c" opacity="0.31"/>
    <path d="M0 334Q200 285 430 325T924 324V498H0Z" fill="url(#floor)"/>
    <path d="M288 339L502 339 690 498H138Z" fill="#e6dfcd" stroke="#b9baa1" stroke-width="2"/>
    <path d="M228 399H572M193 444H628M288 339L341 498M391 339L468 498M468 339L580 498" stroke="#c2c2aa" stroke-width="1" opacity="0.64"/>
    <path d="M529 260H804V351H529Z" fill="#ece0c4" stroke="#8c8e70" stroke-width="2"/>
    <path d="M550 239H785V336H550Z" fill="#e7dcc0"/>
    <path d="M579 263V333M626 263V333M674 263V333M721 263V333M768 263V333" stroke="#8e987b" stroke-width="7"/>
    <path d="M588 273H616V305H588ZM635 273H665V305H635ZM683 273H713V305H683ZM730 273H760V305H730Z" fill="#8b9e88"/>
    <path d="M586 281H618M600 271V307M634 282H666M650 271V307M682 282H714M697 271V307M729 282H761M746 271V307" stroke="#cec7a9" stroke-width="2"/>
    <path d="M516 255Q547 250 574 218H756Q781 248 818 255Q788 266 755 260H576Q546 266 516 255Z" fill="url(#roof)" stroke="#647566" stroke-width="3"/>
    <path d="M544 254H795M585 223L570 251M607 223L598 252M632 223L627 252M656 223V252M681 223L686 252M706 223L716 252M733 223L747 252" stroke="#7f917b" stroke-width="2"/>
    <path d="M522 339H811V349H522ZM539 349H796V357H539ZM551 357H784V365H551Z" fill="#a8ac91" stroke="#7e917c" stroke-width="1"/>
    <ellipse cx="758" cy="439" rx="137" ry="29" fill="#bbcbbb" opacity="0.56"/>
    <path d="M724 437Q766 428 804 433M707 449Q764 441 823 447" fill="none" stroke="#96b6aa" stroke-width="2"/>
    <path d="M46 387Q25 373 50 349L78 341 91 378Z" fill="#919f86"/>
    <path d="M102 366L111 339 133 347 141 369Z" fill="#b3b69b"/>
    <path d="M838 381L849 352 879 343 901 363 898 393Z" fill="#9aa68b"/>
    '''
    rng = random.Random(24)
    for side in [70, 112, 870, 905]:
        tilt = rng.randint(-12, 12)
        body += f'<path d="M{side} 343Q{side+tilt} 240 {side+tilt*2} 156" fill="none" stroke="#748f6d" stroke-width="5" opacity="0.82"/>'
        for yy in [192, 233, 274, 315]:
            body += f'<path d="M{side-5} {yy}h12" stroke="#596f59" stroke-width="2"/>'
            for dx, dy in [(-35, -22), (37, -16), (-45, 8), (40, 12)]:
                body += f'<path d="M{side} {yy}Q{side+dx//2} {yy+dy-9} {side+dx} {yy+dy}Q{side+dx//2} {yy+dy+6} {side} {yy}" fill="#658966" opacity="0.76"/>'
    for _ in range(76):
        x, y = rng.randint(10, 914), rng.randint(365, 486)
        if 190 < x < 650:
            continue
        body += f'<path d="M{x} {y}l-3 -9m3 9l4 -7" stroke="#9ba27a" stroke-width="1.2" opacity="0.6"/>'
    for x, y, radius in [(168, 205, 54), (210, 181, 40), (229, 229, 50), (172, 256, 49), (165, 165, 36)]:
        body += f'<ellipse cx="{x}" cy="{y}" rx="{radius}" ry="{radius*0.62}" fill="#8fa27d" opacity="0.30"/>'
    body += '<path d="M180 313L185 242 166 202M183 251L211 215" stroke="#879175" stroke-width="9" stroke-linecap="round" fill="none" opacity="0.7"/>'
    body += '<path d="M5 9H919V489H5Z" fill="none" stroke="#b7b497" stroke-width="1" opacity="0.45"/>'
    svg('courtyard.svg', 924, 498, body)

def character(mentor=False):
    robe = '#788d80' if mentor else '#4b8d86'
    shadow = '#536b5d' if mentor else '#2b655d'
    body = f'''
    <ellipse cx="130" cy="329" rx="73" ry="12" fill="#647b68" opacity="0.16"/>
    <path d="M85 303L87 332H115L121 301M140 300L147 332H177L177 303" fill="#41453c" stroke="#353d32" stroke-width="3"/>
    <path d="M81 167Q53 189 52 232L78 244 95 205M178 167Q200 176 213 219L193 237 163 201" fill="{robe}" stroke="{shadow}" stroke-width="3"/>
    <path d="M87 163Q127 151 172 164L192 311Q128 328 66 310Z" fill="{robe}" stroke="{shadow}" stroke-width="3"/>
    <path d="M102 163L128 204 153 162 174 171 128 235 85 173Z" fill="#ece4ca" stroke="{shadow}" stroke-width="2"/>
    <path d="M93 178L133 219 106 304H77ZM145 224L166 185 180 309H129Z" fill="{shadow}" opacity="0.32"/>
    <path d="M84 237Q128 249 179 237L181 253Q126 266 82 252Z" fill="#c8ae75" stroke="#887957" stroke-width="2"/>
    <path d="M132 253L139 297" fill="none" stroke="#ac875a" stroke-width="5"/>
    <path d="M113 199L108 234M160 210L165 235M102 275L91 306M148 276L158 313" stroke="#ced8bd" stroke-width="2" opacity="0.55"/>
    <ellipse cx="63" cy="225" rx="14" ry="13" fill="#f1d6b2" stroke="#90745a" stroke-width="2"/>
    <ellipse cx="201" cy="221" rx="14" ry="13" fill="#f1d6b2" stroke="#90745a" stroke-width="2"/>
    <path d="M60 228L61 253 69 267 79 243" fill="none" stroke="#9e916c" stroke-width="3"/>
    <ellipse cx="130" cy="100" rx="60" ry="65" fill="#f2d8b7" stroke="#5e5946" stroke-width="3"/>
    <ellipse cx="71" cy="113" rx="10" ry="17" fill="#edcfaa"/>
    <ellipse cx="188" cy="113" rx="10" ry="17" fill="#edcfaa"/>
    <ellipse cx="92" cy="129" rx="12" ry="5" fill="#dc9683" opacity="0.35"/>
    <ellipse cx="164" cy="129" rx="12" ry="5" fill="#dc9683" opacity="0.35"/>
    '''
    if mentor:
        body += '''
        <path d="M72 92Q65 33 127 28Q189 29 189 92L171 72Q126 83 88 68Z" fill="#46554b" stroke="#37463c" stroke-width="3"/>
        <path d="M89 41Q128 18 170 41L169 61H89Z" fill="#536b5a"/>
        <path d="M91 103Q103 95 118 99M144 99Q159 95 172 105" stroke="#e7e5d4" stroke-width="7" stroke-linecap="round" fill="none"/>
        <path d="M94 115Q103 110 113 115M146 115Q157 110 166 115" stroke="#514c3d" stroke-width="3" fill="none"/>
        <path d="M128 114L123 128 132 130" stroke="#ba9878" stroke-width="2" fill="none"/>
        <path d="M113 137Q129 143 146 136" stroke="#a77a63" stroke-width="2" fill="none"/>
        <path d="M98 142Q91 172 128 198Q165 171 162 143L146 152 129 148 113 155Z" fill="#e4e3d1" stroke="#b0b7a0" stroke-width="2"/>
        <path d="M121 155Q118 174 129 188M137 154Q145 172 130 192" stroke="#c1c6af" stroke-width="2" fill="none"/>
        <path d="M108 136Q94 136 91 147Q105 149 121 138M143 138Q158 136 166 146Q152 151 136 139" fill="#e9e7d5"/>
        '''
    else:
        body += '''
        <path d="M73 103Q58 42 118 28Q180 17 189 81L188 109 171 93 170 69Q141 93 99 85L87 112Z" fill="#46483c" stroke="#353b31" stroke-width="3"/>
        <path d="M105 29Q117 8 138 17L148 34" fill="#45473a" stroke="#353b31" stroke-width="3"/>
        <path d="M107 35L144 33" stroke="#aac39f" stroke-width="7"/>
        <path d="M111 25L141 21M83 61Q122 37 163 44M91 71Q119 65 141 52" stroke="#777768" stroke-width="3" fill="none" opacity="0.66"/>
        <ellipse cx="105" cy="112" rx="11" ry="15" fill="#f9f7e5"/>
        <ellipse cx="157" cy="112" rx="11" ry="15" fill="#f9f7e5"/>
        <ellipse cx="107" cy="114" rx="7" ry="11" fill="#3e5143"/>
        <ellipse cx="155" cy="114" rx="7" ry="11" fill="#3e5143"/>
        <circle cx="109" cy="109" r="3" fill="#fffdf3"/>
        <circle cx="157" cy="109" r="3" fill="#fffdf3"/>
        <path d="M91 93L115 91M146 91L169 94" stroke="#4b4b3e" stroke-width="3" stroke-linecap="round"/>
        <path d="M129 116L125 127 131 129M119 140Q129 148 140 138" stroke="#b78c70" stroke-width="2" fill="none"/>
        <path d="M166 165L172 188 182 179" fill="#e8dbc0"/>
        '''
    svg('songfeng.svg' if mentor else 'qinglan.svg', 260, 350, body)

def main():
    paper()
    courtyard()
    character()
    character(True)
    svg('icon.svg', 128, 128, '<rect x="4" y="4" width="120" height="120" rx="20" fill="#38695b"/><path d="M18 94L48 44 66 70 83 31 113 94Z" fill="#e9e0c6"/><path d="M25 103H105" stroke="#c6a978" stroke-width="5"/>')
    print('Original SVG sketch assets created.')

if __name__ == '__main__':
    main()
