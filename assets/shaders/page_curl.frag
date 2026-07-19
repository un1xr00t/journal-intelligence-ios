#version 460 core
// assets/shaders/page_curl.frag
//
// Cylindrical page-curl for Notebook Mode. The sheet bends around a
// vertical cylinder of radius uRadius whose contact line is at x = uCurlX.
// Right of the cylinder the sheet has left the surface (a soft shadow is
// cast on whatever is beneath); on the cylinder you see the front rolling
// up and the back wrapping over the crest; left of the contact line the
// flipped tail lies flat on top of the not-yet-turned part of the sheet.
//
// All colours are premultiplied; layers composite with source-over so the
// sheet's transparent margins behave correctly from every angle.

#include <flutter/runtime_effect.glsl>

precision highp float;

uniform vec2 uSize;
uniform float uCurlX;
uniform float uRadius;
uniform sampler2D uPage;

out vec4 fragColor;

const float PI = 3.141592653589793;

vec4 samplePage(float px, float py) {
  return texture(uPage, vec2(px / uSize.x, py / uSize.y));
}

// Back of the sheet: paper colour with a hint of ink bleed-through.
vec4 backFace(float px, float py) {
  vec4 s = samplePage(px, py);
  vec3 paper = vec3(0.955, 0.935, 0.870);
  return vec4(mix(paper * s.a, s.rgb, 0.16), s.a);
}

// Premultiplied source-over.
vec4 over(vec4 top, vec4 bottom) {
  return top + bottom * (1.0 - top.a);
}

void main() {
  vec2 xy = FlutterFragCoord().xy;
  float w = uSize.x;
  float x = xy.x;
  float y = xy.y;
  float c = uCurlX;
  float r = uRadius;
  float d = x - c;

  if (d >= r) {
    // The sheet has fully left this region — soft travelling shadow on
    // the page underneath, fading with distance from the roll.
    float sh = 1.0 - smoothstep(0.0, r * 1.8, d - r);
    fragColor = vec4(0.0, 0.0, 0.0, 0.26 * sh * sh);
    return;
  }

  if (d >= 0.0) {
    // On the cylinder.
    float theta = asin(clamp(d / r, 0.0, 1.0));
    float pFront = c + r * theta;        // sheet coord rolling up the front
    float pBack = c + r * (PI - theta);  // sheet coord wrapping over the top

    vec4 front = vec4(0.0);
    if (pFront <= w) {
      vec4 col = samplePage(pFront, y);
      float dark = 0.62 + 0.38 * cos(theta); // rolls away from the light
      front = vec4(col.rgb * dark, col.a);
    }

    vec4 back = vec4(0.0);
    if (pBack <= w) {
      vec4 col = backFace(pBack, y);
      float light = 0.86 + 0.14 * cos(theta); // brightest at the crest
      back = vec4(col.rgb * light, col.a);
    }

    // Faint contact shadow where neither surface covers.
    float sh = 1.0 - smoothstep(0.0, r * 1.5, d);
    vec4 base = vec4(0.0, 0.0, 0.0, 0.16 * sh);

    fragColor = over(back, over(front, base));
    return;
  }

  // Flat region left of the contact line: the un-turned sheet, shadowed
  // by the approaching roll…
  vec4 flatCol = samplePage(x, y);
  float sh = 1.0 - smoothstep(0.0, r * 1.1, -d);
  flatCol = vec4(flatCol.rgb * (1.0 - 0.20 * sh), flatCol.a);

  // …possibly covered by the flipped tail lying on top of it.
  float pFlat = 2.0 * c - x + PI * r;
  if (pFlat <= w) {
    vec4 tail = backFace(pFlat, y);
    float crease = 1.0 - smoothstep(0.0, r * 0.9, c - x);
    tail = vec4(tail.rgb * (1.0 - 0.10 * crease), tail.a);
    fragColor = over(tail, flatCol);
  } else {
    fragColor = flatCol;
  }
}
