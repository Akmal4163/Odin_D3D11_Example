package multitexture

import d3d11"vendor:directx/d3d11"
import dxgi"vendor:directx/dxgi"
import dxc"vendor:directx/d3d_compiler"
import win32"core:sys/windows"
import stbi"vendor:stb/image"
import glm"core:math/linalg/glsl"
import "core:os"
import "base:intrinsics"
import "base:runtime"
import "core:fmt"

L :: intrinsics.constant_utf16_cstring
device: ^d3d11.IDevice
device_context: ^d3d11.IDeviceContext
swapchain: ^dxgi.ISwapChain
render_target_view: ^d3d11.IRenderTargetView
vertex_shader: ^d3d11.IVertexShader
pixel_shader: ^d3d11.IPixelShader
input_layout: ^d3d11.IInputLayout
vertex_buffer: ^d3d11.IBuffer
index_buffer: ^d3d11.IBuffer
color_buffer: ^d3d11.IBuffer
sampler_state: ^d3d11.ISamplerState

////////////////////////////
texture1: ^d3d11.ITexture2D
texture_view1: ^d3d11.IShaderResourceView

texture2: ^d3d11.ITexture2D
texture_view2: ^d3d11.IShaderResourceView


vertex :: struct {
    pos: glm.vec3,
    texCoord: glm.vec2,
}

vertex_shader_source := `
struct Input {
    float3 position : POSITION;
    float2 texCoord : TEXCOORD;
};

struct Output {
    float4 position : SV_POSITION;
    float2 TexCoord : TEXCOORD;
};

Output vs_main(Input input) {
    Output output;
    output.position = float4(input.position, 1);
    output.TexCoord = input.texCoord;
    
    return output;
}
`

pixel_shader_source := `
Texture2D texture1 : register(t0);
Texture2D texture2 : register(t1);
SamplerState sampleType : register(s0);

struct Input {
    float4 position : SV_POSITION;
    float2 texCoord : TEXCOORD;
};

float4 ps_main(Input input) : SV_TARGET {
    float4 color1 = texture1.Sample(sampleType, input.texCoord);
    float4 color2 = texture2.Sample(sampleType, input.texCoord);

    return lerp(color1, color2, 0.5);
}
`

WindowProc :: proc "system" (hwnd: win32.HWND, uMsg: win32.UINT, wParam: win32.WPARAM, lParam: win32.LPARAM) -> win32.LRESULT {
    context = runtime.default_context()
    if(uMsg == win32.WM_DESTROY) {
        win32.PostQuitMessage(0)
    }

    return win32.DefWindowProcW(hwnd, uMsg, wParam, lParam)
}

init_window :: #force_inline proc(instance: win32.HINSTANCE) -> win32.HWND {

    window_class_name := L("Simple Win32 Window")
    wc: win32.WNDCLASSW
    wc.style = win32.CS_HREDRAW | win32.CS_VREDRAW 
    wc.lpfnWndProc = WindowProc
    wc.hInstance = instance
    wc.lpszClassName = window_class_name

    win32.RegisterClassW(&wc)

    hwnd := win32.CreateWindowW(window_class_name, L("simple window"), win32.WS_OVERLAPPEDWINDOW, win32.CW_USEDEFAULT, win32.CW_USEDEFAULT, 800, 600, nil, nil, instance, nil)

    win32.ShowWindow(hwnd, win32.SW_SHOW)
    win32.UpdateWindow(hwnd)

    return hwnd

}

init_d3d :: proc (hwnd: win32.HWND) {
    
    scd: dxgi.SWAP_CHAIN_DESC

    scd.BufferCount = 1
    scd.BufferDesc.Format = .R8G8B8A8_UNORM
    scd.BufferUsage = {.RENDER_TARGET_OUTPUT}
    scd.OutputWindow = hwnd
    scd.SampleDesc.Count = 1
    scd.Windowed = win32.TRUE

    result := d3d11.CreateDeviceAndSwapChain(nil, .HARDWARE, nil, {.SINGLETHREADED}, nil, 0, d3d11.SDK_VERSION, &scd, &swapchain, &device, nil, &device_context)
    if result != 0 {
        win32.MessageBoxW(hwnd, L("Error"), L("cannot create d3d11 device and swapchain"), win32.MB_ICONERROR)
        win32.ExitProcess(0)
    }

    back_buffer: ^d3d11.ITexture2D
    swapchain->GetBuffer(0, d3d11.ITexture2D_UUID, (^rawptr)(&back_buffer))
    device->CreateRenderTargetView(back_buffer, nil, &render_target_view)
    back_buffer->Release()
}

create_vertex_and_index_buffers :: proc () {

    {
        vertices : []vertex = {
            {{0.5, 0.5, 0.0}, {1.0, 1.0}},
            {{0.5,  -0.5,  0.0}, {1.0, 0.0}},
            {{-0.5, -0.5,  0.0}, {0.0, 0.0}},
            {{-0.5, 0.5, 0.0}, {0.0, 1.0}}
        }

        //vertex buffer
        vertex_buffer_desc: d3d11.BUFFER_DESC
        vertex_buffer_desc.Usage = .DEFAULT
        vertex_buffer_desc.ByteWidth = u32(len(vertices) * size_of(vertex))
        vertex_buffer_desc.BindFlags = {.VERTEX_BUFFER}

        vertex_buffer_data: d3d11.SUBRESOURCE_DATA
        vertex_buffer_data.pSysMem = &vertices[0]

        device->CreateBuffer(&vertex_buffer_desc, &vertex_buffer_data, &vertex_buffer)
    }

    {
        //index buffer
        indices := []u32 {
            0, 1, 2, 0, 2, 3,
        }
        index_buffer_desc: d3d11.BUFFER_DESC
        index_buffer_desc.Usage = .DEFAULT
        index_buffer_desc.ByteWidth = u32(len(indices) * size_of(u32))
        index_buffer_desc.BindFlags = {.INDEX_BUFFER}

        index_buffer_data: d3d11.SUBRESOURCE_DATA
        index_buffer_data.pSysMem = &indices[0]

        device->CreateBuffer(&index_buffer_desc, &index_buffer_data, &index_buffer)
    }

    
}

prepare_texture :: proc () {
    
    {
        //load texture using stb image
        width, height, nr_channels: i32
        image_data := stbi.load("textures/container.jpg", &width, &height, &nr_channels, 4)
        assert(image_data != nil)

        texture_desc: d3d11.TEXTURE2D_DESC
        texture_desc.Width = u32(width)
        texture_desc.Height = u32(height)
        texture_desc.MipLevels = 1
        texture_desc.ArraySize = 1
        texture_desc.Format = .R8G8B8A8_UNORM
        texture_desc.SampleDesc.Count = 1
        texture_desc.Usage = .DEFAULT
        texture_desc.BindFlags ={.SHADER_RESOURCE}

        texture_data: d3d11.SUBRESOURCE_DATA
        texture_data.pSysMem = &image_data[0]
        texture_data.SysMemPitch = u32(width * 4)
        device->CreateTexture2D(&texture_desc, &texture_data, &texture1)
        
        //create shader resource view
        device->CreateShaderResourceView(texture1, nil, &texture_view1)
        
        //create sampler state
        sampler_desc: d3d11.SAMPLER_DESC
        sampler_desc.Filter = .MIN_MAG_MIP_LINEAR
        sampler_desc.AddressU = .WRAP
        sampler_desc.AddressV = .WRAP
        sampler_desc.AddressW = .WRAP

        device->CreateSamplerState(&sampler_desc, &sampler_state)
        stbi.image_free(image_data)
    }

    {
        //load texture using stb image
        width, height, nr_channels: i32
        image_data := stbi.load("textures/awesomeface.png", &width, &height, &nr_channels, 4)
        assert(image_data != nil)

        texture_desc: d3d11.TEXTURE2D_DESC
        texture_desc.Width = u32(width)
        texture_desc.Height = u32(height)
        texture_desc.MipLevels = 1
        texture_desc.ArraySize = 1
        texture_desc.Format = .R8G8B8A8_UNORM
        texture_desc.SampleDesc.Count = 1
        texture_desc.Usage = .DEFAULT
        texture_desc.BindFlags ={.SHADER_RESOURCE}

        texture_data: d3d11.SUBRESOURCE_DATA
        texture_data.pSysMem = &image_data[0]
        texture_data.SysMemPitch = u32(width * 4)
        device->CreateTexture2D(&texture_desc, &texture_data, &texture2)
        
        //create shader resource view
        device->CreateShaderResourceView(texture2, nil, &texture_view2)
        
        //create sampler state
        sampler_desc: d3d11.SAMPLER_DESC
        sampler_desc.Filter = .MIN_MAG_MIP_LINEAR
        sampler_desc.AddressU = .WRAP
        sampler_desc.AddressV = .WRAP
        sampler_desc.AddressW = .WRAP

        device->CreateSamplerState(&sampler_desc, &sampler_state)
        stbi.image_free(image_data)
    }
}

compile_shader_from_source :: proc () {

    vs_blob: ^d3d11.IBlob; defer vs_blob->Release()
    dxc.Compile(raw_data(vertex_shader_source), len(vertex_shader_source), nil, nil, nil, "vs_main", "vs_5_0", 0, 0, &vs_blob, nil)
    assert(vs_blob != nil)
    device->CreateVertexShader(vs_blob->GetBufferPointer(), vs_blob->GetBufferSize(), nil, &vertex_shader)

    ps_blob: ^d3d11.IBlob; defer ps_blob->Release()
    dxc.Compile(raw_data(pixel_shader_source), len(pixel_shader_source), nil, nil, nil, "ps_main", "ps_5_0", 0, 0, &ps_blob, nil)
    assert(ps_blob != nil)
    device->CreatePixelShader(ps_blob->GetBufferPointer(), ps_blob->GetBufferSize(), nil, &pixel_shader)
    
    layout := [?]d3d11.INPUT_ELEMENT_DESC {
        { "POSITION", 0, .R32G32B32_FLOAT, 0, 0, .VERTEX_DATA, 0 },
        { "TEXCOORD", 0, .R32G32_FLOAT, 0, 0, .VERTEX_DATA, 0},
    }

    device->CreateInputLayout(&layout[0], len(layout), vs_blob->GetBufferPointer(), vs_blob->GetBufferSize(), &input_layout)
}

draw_frame :: proc () {
    viewport := d3d11.VIEWPORT{
        0, 0, 800, 600, 0, 0
    }
    stride := u32(size_of(vertex))
    offset := u32(0)
    device_context->IASetInputLayout(input_layout)
    device_context->IASetVertexBuffers(0, 1, &vertex_buffer, &stride, &offset)
    device_context->IASetIndexBuffer(index_buffer, .R32_UINT, 0)
    device_context->IASetPrimitiveTopology(.TRIANGLELIST)
    device_context->VSSetShader(vertex_shader, nil, 0)
    device_context->PSSetShader(pixel_shader, nil, 0)

    ///////////////////////////////////
    device_context->PSSetShaderResources(0, 1, &texture_view1)
    device_context->PSSetShaderResources(1, 1, &texture_view2)
    ///////////////////////////////////
    device_context->PSSetSamplers(0, 1, &sampler_state)
    device_context->OMSetRenderTargets(1, &render_target_view, nil)
    device_context->OMSetBlendState(nil, nil, ~u32(0))
    device_context->RSSetViewports(1, &viewport)
    device_context->DrawIndexed(6, 0, 0)
}

update :: proc () {
    clear_color := [4]f32{0.0, 0.0, 0.0, 1.0}
    device_context->ClearRenderTargetView(render_target_view, &clear_color)

    draw_frame()
    
    swapchain->Present(1, {})

}

mainloop :: proc () -> int {
    instance := win32.HINSTANCE(win32.GetModuleHandleW(nil))
    if (instance == nil) {fmt.println("No instance")}
    hwnd := init_window(instance)
    if hwnd == nil {
        fmt.println("Failed to create window")
        return 0
    }

    init_d3d(hwnd)
    create_vertex_and_index_buffers()
    prepare_texture()
    compile_shader_from_source()
    
    msg : win32.MSG
    for msg.message != win32.WM_QUIT {
        if(win32.PeekMessageW(&msg, nil, 0, 0, win32.PM_REMOVE)) {
            win32.TranslateMessage(&msg)
            win32.DispatchMessageW(&msg)
            if(msg.message == win32.WM_QUIT) {
                break
            }
        } 
            
        update()
    }

    cleanup()
    return int(msg.wParam)
}

cleanup :: proc () {
    if (input_layout != nil) { input_layout->Release()}
    if (vertex_shader != nil) { vertex_shader->Release()}
    if (pixel_shader != nil) { pixel_shader->Release()}
    if (render_target_view != nil) { render_target_view->Release()}
    if (swapchain != nil) { swapchain->Release()}
    if (device_context != nil) { device_context->Release()}
    if (device != nil) { device->Release()}
    if (texture1 != nil) { texture1->Release()}
    if (texture2 != nil) { texture2->Release()}
    if (texture_view1 != nil) { texture_view1->Release()}
    if (texture_view2 != nil) { texture_view2->Release()}
}

main :: proc () {
    exit_code := mainloop()
    os.exit(exit_code)
}