// One bounded source-shape diagnostic; compiler checkout stays unchanged.
import * as fs from 'node:fs';
import * as B from 'file:///Users/chuah/Documents/ChatGPT/bendex/bend/bend2/bend.ts';
const dir=process.argv[2], entry=process.argv[3];
let src=fs.readFileSync('/Users/chuah/Documents/ChatGPT/bendex/bend/bend2/comp.ts','utf8');
src=src.replace('"./bend.ts"','"file:///Users/chuah/Documents/ChatGPT/bendex/bend/bend2/bend.ts"');
src=src.replace('return memo(FUNS, k, () => {','return memo(FUNS, k, () => { process.stderr.write(JSON.stringify({fun:k,heap:process.memoryUsage().heapUsed})+"\\n");');
fs.writeFileSync(dir+'/comp.ts',src);
const Comp=await import('file://'+dir+'/comp.ts');
const book=B.book_nil();await B.book_load(book,entry,'',new Map());B.book_valid(book);
process.stderr.write('ordinary complete\n');const output=Comp.compile_book(book);fs.writeFileSync(dir+'/diagnostic.c',output);
