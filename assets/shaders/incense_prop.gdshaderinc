// Scene-specific source-pixel silhouette in the unchanged 2146 x 733 desk art.
// The transparent upper area keeps the original fine lid edges; the traced
// lower outline excludes tabletop pixels when the censer is rendered taller.
const vec2 INCENSE_OUTLINE[26] = vec2[26](
 vec2(1149.,315.), vec2(1351.,315.), vec2(1351.,425.), vec2(1340.,425.),
 vec2(1337.,442.), vec2(1326.,458.), vec2(1310.,467.), vec2(1318.,480.),
 vec2(1310.,500.), vec2(1296.,500.), vec2(1290.,481.), vec2(1269.,481.),
 vec2(1264.,497.), vec2(1255.,506.), vec2(1234.,506.), vec2(1224.,498.),
 vec2(1223.,482.), vec2(1215.,480.), vec2(1206.,498.), vec2(1190.,498.),
 vec2(1182.,490.), vec2(1183.,466.), vec2(1172.,461.), vec2(1160.,446.),
 vec2(1158.,425.), vec2(1149.,425.)
);
float incense_silhouette(vec2 p) {
 bool inside = false;
 float distance_to_edge = 1000.;
 for (int i = 0; i < 26; i++) {
  vec2 a = INCENSE_OUTLINE[i];
  vec2 b = INCENSE_OUTLINE[(i + 1) % 26];
  if ((a.y > p.y) != (b.y > p.y)) {
   if (p.x < (b.x - a.x) * (p.y - a.y) / (b.y - a.y) + a.x) { inside = !inside; }
  }
  vec2 ab = b - a;
  float along = clamp(dot(p - a, ab) / max(dot(ab, ab), .001), 0., 1.);
  distance_to_edge = min(distance_to_edge, length(p - a - ab * along));
 }
 return inside ? smoothstep(0., .9, distance_to_edge) : 0.;
}
