import assert from 'node:assert/strict';
import { timingSafeEqual } from 'node:crypto';
import { identify } from '../src/auth.ts';
crypto.subtle.timingSafeEqual = (a,b) => timingSafeEqual(Buffer.from(a),Buffer.from(b));
const env={MEMBER_BINDINGS_JSON:JSON.stringify({'member-one':'MEMBER_ONE_KEY','member-two':'MEMBER_TWO_KEY'}),MEMBER_ONE_KEY:'first-test-key',MEMBER_TWO_KEY:'second-test-key'};
const request=key=>new Request('https://example.com/api/me',{headers:key?{Authorization:`Bearer ${key}`}:{}});
assert.equal(await identify(request('first-test-key'),env),'member-one');
assert.equal(await identify(request('second-test-key'),env),'member-two');
assert.equal(await identify(request('wrong-key'),env),null);
assert.equal(await identify(request(),env),null);
for(const value of ['', '{broken', '[]', 'null', '{"member-one":"MISSING"}', '{"member-one":12}', '{"member-one":"bad-binding"}']){
 assert.equal(await identify(request('first-test-key'),{...env,MEMBER_BINDINGS_JSON:value}),null);
}
assert.equal(await identify(request('first-test-key'),{...env,MEMBER_ONE_KEY:''}),null);
console.log('Treehouse authentication: existing IDs resolve correctly; missing, invalid, and malformed credentials deny access.');
