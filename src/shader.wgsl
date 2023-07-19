struct VertexInput {
    @location(0) position: vec2<f32>,
    @location(1) color: vec3<f32>,
}

struct VertexOutput {
    @builtin(position) clip_position: vec4<f32>,
    @location(0) color: vec3<f32>,
}

struct Uniforms {
    time: f32,
    width: f32,
    height: f32,
}

@group(0) @binding(0) var<uniform> uni: Uniforms;

fn palette(t: f32 )  ->  vec3<f32>  {
    let a = vec3(0.5,0.5,0.5);
    let b = vec3(0.5,0.5,0.5);
    let c = vec3(1.0,1.0,1.0);
    let d = vec3(0.263,0.416, 0.557);

    return a + b*cos(6.28318*(c*t+d));
}

@vertex 
fn vs_main( model: VertexInput ) -> VertexOutput {
    var out: VertexOutput;
    out.color = model.color;
    out.clip_position = vec4<f32>(model.position, 0.0, 1.0);
    return out;
}

@fragment 
fn fs_main( in: VertexOutput ) -> @location(0) vec4<f32> {
    let time = uni.time / 1000.0;
    var uv = vec2(in.clip_position.x / uni.width, in.clip_position.y / uni.height);
    uv = uv * 2.0 - 1.0;
    uv.x *= uni.width / uni.height;
    uv.y *= uni.width / uni.height;

    let uv0 = uv;
    var final_color = vec3(0.0);

    for (var i: f32 = 0.0; i < 4.0; i+= 1.0) {
        uv = fract(uv * 1.5) - 0.5;

        var d = length(uv) * exp(-length(uv0));

        var col = palette(length(uv0)+ i * 0.4 + time * 0.4);

        d = sin(d * 8.0 + time) / 8.0;
        d = abs(d);
        d = pow(0.01/ d, 1.2);

        final_color += col * d;
    }

    return vec4(final_color, 1.0);
}
