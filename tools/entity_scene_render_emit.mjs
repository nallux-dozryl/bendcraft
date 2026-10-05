import * as B from 'file:///Users/chuah/Documents/ChatGPT/bendex/bend/bend2/bend.ts';
import * as Comp from 'file:///Users/chuah/Documents/ChatGPT/bendex/bend/bend2/comp.ts';
import * as fs from 'node:fs';import * as crypto from 'node:crypto';
process.on('uncaughtException',e=>{console.error(e?.$==='Err'?B.err_show(e):e);process.exit(1)});
const [entry,out]=process.argv.slice(2),book=B.book_nil(),seen=new Map();
if(process.env.ENTITY_SCENE_RENDER_TRACE){const push=book.order.push;book.order.push=function(...v){for(const x of v)console.log('Parsed '+x);return push.apply(this,v)}}
await B.book_load(book,entry,'',seen);console.log('Loaded '+book.order.length+' declarations');
const sha=x=>crypto.createHash('sha256').update(x).digest('hex');const before=Object.fromEntries([...seen.keys()].sort().map(p=>[p,sha(fs.readFileSync(p))]));
if(process.env.ENTITY_SCENE_RENDER_TRACE){const counts=new Map();book.order=new Proxy(book.order,{get(t,k){const v=Reflect.get(t,k);if(typeof k==='string'&&/^\d+$/.test(k)){const n=(counts.get(k)||0)+1;counts.set(k,n);if(n===2)console.log('Checking '+v)}return v}})}
B.book_valid(book);console.log('Checked original book');if(book.hols)throw Error('Open holes');
if(out){if(global.gc)global.gc();fs.writeFileSync(out,Comp.compile_book(book));for(const[p,h]of Object.entries(before))if(sha(fs.readFileSync(p))!==h)throw Error('Source changed '+p);fs.writeFileSync(out+'.sources.json',JSON.stringify({entry,source_sha256:before,compiler_sha256:sha(fs.readFileSync('/Users/chuah/Documents/ChatGPT/bendex/bend/bend2/comp.ts')),ordinary_checked_original_book:true},null,2)+'\n')}
