package triangle

import d3d11"vendor:directx/d3d11"
import dxgi"vendor:directx/dxgi"
import dxc"vendor:directx/d3d_compiler"
import win32"core:sys/windows"
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


vertex :: struct {
    pos: glm.vec2,
    col: glm.vec3,
}

vertex_shader_source := `
struct Input {
    float2 position : POSITION;
    float3 color : COLOR;
};

struct Output {
    float4 position : SV_POSITION;
    float3 color : COLOR;
};

Output vs_main(Input input) {
    Output output;
    output.position = float4(input.position.x, input.position.y, 0, 1);
    output.color = input.color;

    return output;
}
`

pixel_shader_source := `
struct Input {
    float4 position : SV_POSITION;
    float3 color : COLOR;
};

float4 ps_main(Input input) : SV_TARGET {
    return float4(input.color.r, input.color.g, input.color.b, 1);
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

render_triangle :: proc () {
    vertices : []vertex = {
        {{-0.5, -0.5}, {1.0, 0.0, 0.0}},
        {{0.0,  0.5}, {0.0, 1.0, 0.0}},
        {{0.5, -0.5}, {0.0, 0.0, 1.0}},
    }

    bd: d3d11.BUFFER_DESC
    bd.ByteWidth = u32(len(vertices) * size_of(vertex))
    bd.BindFlags = {.VERTEX_BUFFER}

    init_data: d3d11.SUBRESOURCE_DATA
    init_data.pSysMem = &vertices[0]

    device->CreateBuffer(&bd, &init_data, &vertex_buffer)
}

draw_triangle :: proc () {
    device_context->IASetInputLayout(input_layout)
    device_context->VSSetShader(vertex_shader, nil, 0)
    device_context->PSSetShader(pixel_shader, nil, 0)
    stride := u32(size_of(vertex))
    offset := u32(0)
    device_context->IASetVertexBuffers(0, 1, &vertex_buffer, &stride, &offset)
    device_context->IASetPrimitiveTopology(.TRIANGLELIST)
    device_context->Draw(3, 0)
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
        { "POSITION", 0, .R32G32_FLOAT, 0, 0, .VERTEX_DATA, 0 },
        { "COLOR", 0, .R32G32B32_FLOAT, 0, d3d11.APPEND_ALIGNED_ELEMENT, .VERTEX_DATA, 0 },
    }

    device->CreateInputLayout(&layout[0], len(layout), vs_blob->GetBufferPointer(), vs_blob->GetBufferSize(), &input_layout)
}

update :: proc () {

    device_context->OMSetRenderTargets(1, &render_target_view, nil)
    viewport := d3d11.VIEWPORT{
        0, 0, 800, 600, 0,0
    }
    device_context->RSSetViewports(1, &viewport)
    clear_color := [4]f32{0.0, 0.0, 0.0, 1.0}
    device_context->ClearRenderTargetView(render_target_view, &clear_color)

   
    draw_triangle()
    
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
    render_triangle()
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
}

main :: proc () {
    exit_code := mainloop()
    os.exit(exit_code)
}