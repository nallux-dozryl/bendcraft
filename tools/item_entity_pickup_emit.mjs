// Bounded Node execution of the pinned compiler's unchanged production API.
import * as B from 'file:///Users/chuah/Documents/ChatGPT/bendex/bend/bend2/bend.ts';
process.on('uncaughtException',e=>{console.error(e?.$==='Err'?B.err_show(e):e);process.exit(1)});
import * as Comp from 'file:///Users/chuah/Documents/ChatGPT/bendex/bend/bend2/comp.ts';
import * as fs from 'node:fs';
import * as crypto from 'node:crypto';
const [entry,out]=process.argv.slice(2),book=B.book_nil(),seen=new Map();
await B.book_load(book,entry,'',seen);console.log('Loaded '+book.order.length+' declarations');
const sha=x=>crypto.createHash('sha256').update(x).digest('hex');
const before=Object.fromEntries([...seen.keys()].sort().map(p=>[p,sha(fs.readFileSync(p))]));
B.book_valid(book);console.log('Checked original book');if(book.hols)throw Error('Open holes');
fs.writeFileSync(out,Comp.compile_book(book));
for(const [p,h] of Object.entries(before))if(sha(fs.readFileSync(p))!==h)throw Error('Source changed '+p);
fs.writeFileSync(out+'.sources.json',JSON.stringify({entry,source_sha256:before,compiler_sha256:sha(fs.readFileSync('/Users/chuah/Documents/ChatGPT/bendex/bend/bend2/comp.ts')),ordinary_checked_original_book:true},null,2)+'\n');
