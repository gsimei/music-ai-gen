const fs = require('fs');
const path = require('path');
const { Resvg } = require('/private/tmp/virajingle-marketing-render/node_modules/@resvg/resvg-js');
const root = path.resolve(__dirname, '..');
const project = path.resolve(root, '../../..');
const C = { cream:'#f6f5ed', green:'#173e32', lime:'#c1f66b', muted:'#66746c' };
const fonts = ['Manrope-Regular.ttf','Manrope-Bold.ttf','Manrope-ExtraBold.ttf','CormorantGaramond-SemiboldItalic.ttf'].map(n=>path.join(__dirname,n));
const uri = p => 'data:image/'+(p.endsWith('.svg')?'svg+xml':p.endsWith('.jpg')?'jpeg':'png')+';base64,'+fs.readFileSync(p).toString('base64');
const logo = uri(path.join(project,'public/brand/musical/virajingle-logo.png'));
const logoWhite = uri(path.join(project,'public/brand/musical/virajingle-logo-white.png'));
const photos = Object.fromEntries(['loja-roupas','loja-calcados','salao-beleza'].map(n=>[n,uri(path.join(root,'assets',n+'.png'))]));
photos.pizza = uri(path.join(project,'public/demos/sabores-da-vila-foto-3.jpg'));
const esc = t => String(t).replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;').replace(/"/g,'&quot;');
const rect=(x,y,w,h,fill,rx=0)=>`<rect x="${x}" y="${y}" width="${w}" height="${h}" rx="${rx}" fill="${fill}"/>`;
const text=(x,y,t,size=30,weight=400,fill=C.green,opts={})=>`<text x="${x}" y="${y}" font-family="${opts.serif?'Cormorant Garamond':'Manrope'}" font-size="${size}" font-weight="${weight}" fill="${fill}"${opts.serif?' font-style="italic"':''}${opts.spacing?' letter-spacing="'+opts.spacing+'"':''}${opts.anchor?' text-anchor="'+opts.anchor+'"':''}>${esc(t)}</text>`;
const img=(src,x,y,w,h,rx=0)=>`<svg x="${x}" y="${y}" width="${w}" height="${h}" viewBox="0 0 ${w} ${h}"><defs><clipPath id="clip"><rect width="${w}" height="${h}" rx="${rx}"/></clipPath></defs><image href="${src}" width="${w}" height="${h}" preserveAspectRatio="xMidYMid slice" clip-path="url(#clip)"/></svg>`;
const wordmark=(x,y,w=330,white=false)=>`<image href="${white?logoWhite:logo}" x="${x}" y="${y}" width="${w}" height="${w*763/3200}"/>`;
const pill=(x,y,w,h,label,{fill=C.green,color=C.cream,size=25}={})=>rect(x,y,w,h,fill,h/2)+text(x+w/2,y+h/2+size*.35,label,size,800,color,{anchor:'middle'});
const wave=(x,y,scale=1,color=C.lime)=>`<g transform="translate(${x} ${y}) scale(${scale})" fill="${color}">${[22,40,68,92,58,116,80,52,72,36,16].map((h,i)=>rect(i*17,60-h/2,10,h,color,5)).join('')}</g>`;
const underline=(x,y,w)=>`<path d="M${x} ${y} Q ${x+w*.5} ${y-20} ${x+w} ${y+1}" fill="none" stroke="${C.lime}" stroke-width="13" stroke-linecap="round"/>`;
function render(name,w,h,body){
 const svg=`<svg xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink" width="${w}" height="${h}" viewBox="0 0 ${w} ${h}">${rect(0,0,w,h,C.cream)}${body}</svg>`;
 const base=path.join(root,name);fs.mkdirSync(path.dirname(base),{recursive:true});
 fs.writeFileSync(base+'.svg',svg);
 const r=new Resvg(svg,{font:{fontFiles:fonts,loadSystemFonts:false,defaultFontFamily:'Manrope'},fitTo:{mode:'original'}});
 fs.writeFileSync(base+'.png',r.render().asPng());
 console.log(name,w,h);
}
function postFooter(){return text(64,1163,'Música + vídeo + legenda',32,800)+pill(64,1193,526,71,'R$ 29,90 por campanha',{fill:C.lime,color:C.green,size:32})+pill(620,1193,396,71,'Link na bio →',{size:28})+text(66,1307,'Pagamento único. Sem assinatura.',22,500);}
const postData=[
 {name:'posts/01-sua-loja-merece-um-refrao',photo:'loja-roupas',tag:'LOJAS DE ROUPAS',a:'Sua loja',b:'merece um',c:'refrão.',cs:145,sub:'Suas fotos. Sua oferta. Sua marca na música.'},
 {name:'posts/02-sua-vitrine-ganhou-som',photo:'loja-calcados',tag:'CALÇADOS E ACESSÓRIOS',a:'Sua vitrine',b:'ganhou um',c:'novo som.',cs:136,sub:'Seus produtos em uma campanha com a sua cara.'},
 {name:'posts/03-seu-negocio-tem-ritmo',photo:'salao-beleza',tag:'SALÕES E SERVIÇOS',a:'Sua oferta',b:'no ritmo do',c:'seu negócio.',cs:128,sub:'Para lojas, salões, barbearias e muito mais.'}
];
for(const p of postData){
 let b=wordmark(61,49,330)+text(66,174,'FEITO PARA O SEU NEGÓCIO',17,700,C.green,{spacing:3});
 b+=text(60,287,p.a,100,800)+text(60,393,p.b,100,800)+text(64,526,p.c,p.cs,600,C.green,{serif:true})+underline(71,538,480);
 b+=text(66,595,p.sub,28,500)+img(photos[p.photo],64,638,952,441,26);
 b+=pill(87,662,p.tag.length>20?330:280,48,p.tag,{fill:C.cream,color:C.green,size:17});
 b+=wave(724,927,.85)+`<circle cx="945" cy="980" r="44" fill="${C.green}"/><path d="M933 958 L933 1002 L966 980 Z" fill="${C.lime}"/>`;
 b+=text(66,1107,'Foto ilustrativa criada com IA.',15,400,C.muted)+postFooter();
 render(p.name,1080,1350,b);
}
function storyTop(kicker){return wordmark(77,252,350)+text(82,409,kicker,18,700,C.green,{spacing:3});}
function storyCTA(label='Crie sua campanha · Link na bio'){return pill(80,1600,920,84,label,{size:29});}
let s=storyTop('PARA LOJAS E SERVIÇOS');
s+=text(77,535,'Sua loja',108,800)+text(77,651,'merece um',108,800)+text(82,796,'refrão.',157,600,C.green,{serif:true})+underline(87,812,500);
s+=img(photos['loja-roupas'],80,888,920,474,28)+pill(104,912,283,50,'LOJAS DE ROUPAS',{fill:C.cream,color:C.green,size:18});
s+=text(83,1430,'Suas fotos. Sua oferta.',35,700)+text(83,1483,'Sua marca na música.',35,700)+text(83,1541,'Música + vídeo + legenda',27,500)+storyCTA();
render('stories/01-sua-loja-tem-refrao',1080,1920,s);
s=storyTop('COMO FUNCIONA');
s+=text(77,536,'Da sua vitrine',91,800)+text(77,645,'para o',108,800)+text(82,788,'play.',159,600,C.green,{serif:true})+underline(87,808,355);
s+=img(photos['loja-calcados'],80,870,920,452,28);
for(const [i,t] of ['Envie suas fotos','Conte a oferta','Escolha a música'].entries()){
 let y=1398+i*62;s+=`<circle cx="106" cy="${y-10}" r="22" fill="${C.lime}"/>`+text(106,y-2,i+1,21,800,C.green,{anchor:'middle'})+text(145,y,t,31,700);
}
s+=storyCTA();render('stories/02-da-vitrine-para-o-play',1080,1920,s);
s=storyTop('SUA PRÓXIMA PROMOÇÃO');
s+=text(77,535,'Música, vídeo',92,800)+text(77,645,'e legenda.',108,800)+text(82,790,'Tudo junto.',137,600,C.green,{serif:true})+underline(87,809,632);
s+=img(photos['salao-beleza'],80,870,920,452,28)+pill(104,894,298,50,'SALÕES E SERVIÇOS',{fill:C.cream,color:C.green,size:18});
s+=text(80,1455,'R$ 29,90',84,800)+text(83,1512,'por campanha',30,600)+text(83,1560,'Pagamento único. Sem assinatura.',25,500)+storyCTA();
render('stories/03-campanha-completa',1080,1920,s);
// Full-size scenes for the presentation video; text is typeset, not invented UI.
function videoTop(kicker){return wordmark(77,245,350)+text(82,397,kicker,18,700,C.green,{spacing:3});}
function videoFoot(label){return text(82,1620,label,28,600);}
let v=videoTop('SUA MARCA NA MÚSICA');
v+=text(76,535,'Sua promoção',100,800)+text(76,649,'merece um',108,800)+text(82,796,'refrão.',157,600,C.green,{serif:true})+underline(88,815,500);
const tiles=[['loja-roupas','Moda'],['loja-calcados','Calçados'],['salao-beleza','Beleza'],['pizza','Sabores']];
tiles.forEach(([key,label],i)=>{const x=80+i*234;v+=img(photos[key],x,927,218,436,24)+text(x+109,1419,label,23,700,C.green,{anchor:'middle'});});
v+=text(82,1512,'Para lojas, serviços e comércio local.',33,700)+videoFoot('Suas fotos. Sua oferta. Sua marca na música.');
render('video/cenas/01-abertura',1080,1920,v);
for(const p of [
 {n:'02-lojas',key:'loja-roupas',k:'LOJAS DE ROUPAS',a:'Da sua loja',b:'para o',c:'play.',cs:157,foot:'Sua coleção. Sua oferta. Seu refrão.'},
 {n:'03-vitrine',key:'loja-calcados',k:'CALÇADOS E ACESSÓRIOS',a:'Sua vitrine',b:'ganhou',c:'um novo som.',cs:124,foot:'Seus produtos com a cara da sua marca.'},
 {n:'04-servicos',key:'salao-beleza',k:'SALÕES, BARBEARIAS E MAIS',a:'Cada negócio',b:'tem seu',c:'ritmo.',cs:157,foot:'Da novidade da semana à promoção especial.'}
]){
 v=videoTop(p.k)+text(77,536,p.a,98,800)+text(77,650,p.b,108,800)+text(82,795,p.c,p.cs,600,C.green,{serif:true})+underline(88,814,510);
 v+=img(photos[p.key],80,889,920,596,28)+videoFoot(p.foot);
 render('video/cenas/'+p.n,1080,1920,v);
}
v=videoTop('POUCA COMPLICAÇÃO. MUITO RITMO.');
v+=text(77,548,'Você toca',108,800)+text(77,662,'o negócio.',108,800)+text(82,805,'A gente cria.',136,600,C.green,{serif:true})+underline(88,823,650);
const steps=[['loja-roupas','Envie suas fotos','Use as fotos do seu celular.'],['loja-calcados','Conte a oferta','Seu negócio no centro da campanha.'],['salao-beleza','Escolha a música','Baixe o vídeo, o áudio e a legenda.']];
steps.forEach(([key,title,sub],i)=>{let y=922+i*198;v+=img(photos[key],80,y,182,161,20)+pill(284,y+6,53,53,''+(i+1),{fill:C.lime,color:C.green,size:23})+text(357,y+47,title,34,800)+text(287,y+112,sub,24,500);});
v+=videoFoot('Deu play? Pode postar.');
render('video/cenas/05-como-funciona',1080,1920,v);
v=rect(0,0,1080,1920,C.green)+wordmark(77,245,350,true)+text(82,397,'COLOQUE SUA LOJA PRA TOCAR',18,700,C.lime,{spacing:3});
v+=text(77,550,'Sua próxima',100,800,C.cream)+text(77,664,'promoção',108,800,C.cream)+text(82,810,'já tem ritmo.',135,600,C.lime,{serif:true});
v+=rect(80,935,920,453,C.cream,32)+text(126,1017,'Música + vídeo + legenda',39,800)+text(121,1160,'R$ 29,90',117,800)+text(126,1223,'por campanha',37,600)+text(126,1312,'Pagamento único. Sem assinatura.',28,500);
v+=pill(80,1472,920,100,'Crie sua campanha · Link na bio',{fill:C.lime,color:C.green,size:32})+text(540,1640,'ViraJingle. Sua marca no refrão.',30,600,C.cream,{anchor:'middle'});
render('video/cenas/06-crie-sua-campanha',1080,1920,v);
