if (wls_gamma != 1.0 || wls_saturation != 1.0) {
  if (cogl_texel.a > 0.0) {
    vec3 rgb = pow(max(cogl_texel.rgb / cogl_texel.a, vec3(0.0)), vec3(1.0 / wls_gamma));
    vec3 linear_rgb = mix(pow((rgb + 0.055) / 1.055, vec3(2.4)), rgb / 12.92, lessThanEqual(rgb, vec3(0.04045)));
    float luma = dot(linear_rgb, vec3(0.2126, 0.7152, 0.0722));
    linear_rgb = max(mix(vec3(luma), linear_rgb, wls_saturation), vec3(0.0));
    rgb = mix(1.055 * pow(linear_rgb, vec3(1.0 / 2.4)) - 0.055, 12.92 * linear_rgb, lessThanEqual(linear_rgb, vec3(0.0031308)));
    cogl_texel.rgb = rgb * cogl_texel.a;
  } else { cogl_texel.rgb = vec3(0.0); }
}