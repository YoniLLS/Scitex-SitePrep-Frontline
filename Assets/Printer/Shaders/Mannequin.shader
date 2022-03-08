Shader "Custom/Mannequin"
{
    Properties
    {
		_Color("Color", Color) = (0,0,0,1)

		_ClipAbove("Clip above", Float) = 6.0

		// Grid
		[Space(10)]
		_TriplanarWidth("Triplanar width", Float) = 2.5
		_TriplanarMap("Texture", 2D) = "white" {}
		_TriplanarMapScale("Scale", Range(0.0, 10.0)) = 0.5

		_GridTint("Grid Tint", Color) = (1,1,1,1)
		_GridTintEnd("Grid Tint End", Color) = (1,1,1,1)

		// Scanlines
		[Space(10)]
		_ScanlineTint("Scanline Tint", Color) = (0.25, 0.25, 0.25, 1)
		_ScanlineWidth("Scanline Width", Float) = 1
		_ScanlineSpeed("Scanline Speed", Float) = 1

		_SpreadInside("Spread inside", Float) = 1.0
		_BorderThinness("Border thinness", Float) = 1.0

		[PerRendererData][Toggle(_USE_OVERLAY)] _UseOverlay("Use Overlay", Float) = 1.0
		[PerRendererData][Toggle(_USE_GAZE_MASK)] _UseGazeMask("Use Gaze Mask", Float) = 1.0
		[PerRendererData] _OverlayColor("Overlay Color", Color) = (0, 0, 0, 0)
    }

    SubShader
    {
        Tags { "RenderType"="Opaque" }
        LOD 100

		Pass
		{
			Cull Front
			ZWrite On
			Blend SrcAlpha One

			CGPROGRAM
			#pragma vertex vert
			#pragma fragment frag
			#pragma target 5.0
			#pragma only_renderers d3d11
			#pragma shader_feature _USE_OVERLAY

			#include "UnityCG.cginc"
			#include "UnityStandardConfig.cginc"

			struct appdata
			{
				float4 vertex : POSITION;
				float3 normal : NORMAL;
				float2 uv : TEXCOORD0;
				UNITY_VERTEX_INPUT_INSTANCE_ID
			};


			struct v2f
			{
				half4 vertex : SV_POSITION;
				half3 uvAndClippingHeight : TEXCOORD0;
				half premNDotV : TEXCOORD3;
				UNITY_VERTEX_OUTPUT_STEREO
			};

			half _ClipAbove;
			half4 _GridTint;
			half4 _Color;
			half _SpreadInside;
			half4 _OverlayColor;

			v2f vert(appdata v)
			{
				UNITY_SETUP_INSTANCE_ID(v);

				v2f o;

				o.vertex = UnityObjectToClipPos(v.vertex);
				o.uvAndClippingHeight.xy = v.uv;

				// switch to local space; world space has additional requirements/needs on object rotation
				//o.posWorld = mul(unity_ObjectToWorld, v.vertex).xyz;
				o.uvAndClippingHeight.z = _ClipAbove - v.vertex.y;
				
				float3 viewDir = WorldSpaceViewDir(v.vertex).xyz;
				float3 normalWorld = UnityObjectToWorldNormal(v.normal);
				o.premNDotV = abs(dot(normalWorld, normalize(viewDir)));
				o.premNDotV = 1 - pow(o.premNDotV, _SpreadInside);

				UNITY_INITIALIZE_VERTEX_OUTPUT_STEREO(o);
				return o;
			}


			// ---------------------------------------
			// FRAGMENT SHADER
			// ---------------------------------------
			half4 frag(v2f i) : SV_Target
			{
				clip(i.uvAndClippingHeight.z);

				half4 col = _Color;
				col.a *= i.premNDotV;

				return _OverlayColor * _OverlayColor.a + col;
				return col;
			}
			ENDCG
		}


        Pass
        {
			Blend SrcAlpha One
			ZWrite On

			CGPROGRAM
			#pragma vertex vert
			#pragma fragment frag
			#pragma target 5.0
			#pragma only_renderers d3d11
			#pragma shader_feature _USE_OVERLAY

			#include "UnityCG.cginc"
			#include "UnityStandardConfig.cginc"

			struct appdata
			{
				float4 vertex : POSITION;
				float3 normal : NORMAL;
				float2 uv : TEXCOORD0;
				float4 color : COLOR;
				UNITY_VERTEX_INPUT_INSTANCE_ID
			};


			struct v2f
			{
				half4 vertex : SV_POSITION;
				half3 normalObj : NORMAL;
				//half4 color : COLOR;
				half2 uv : TEXCOORD0;
				/// xyz = localPos.pos.xyz / _TriplanarMapScale, w = localPos.y
				half4 scaledWorldPosAndClippingHeight : TEXCOORD1;
				/// xyz = reflection, w = exp2(-9.28 * nDotV)
				half4 reflectionAndExpNDotV : TEXCOORD2;
				half premNDotV : TEXCOORD3;
				half height : TEXCOORD4;
				UNITY_VERTEX_OUTPUT_STEREO
			};


			sampler2D _TriplanarMap;
			half4 _Color;
			half4 _GridTint, _GridTintEnd;
			half _Roughness, _RoughnessMin, _TriplanarMapScale;
			half _TriplanarWidth;
			half _ClipAbove;
			half4 _ScanlineTint;
			half _ScanlineSpeed, _ScanlineWidth;
			half _BorderThinness;
			uniform half4 _OverlayColor;



			// ---------------------------------------
			// FUNCTIONS
			// ---------------------------------------
			half CalculateTriplanar(half3 WorldBasedUVs, half3 AbsWorldNormal)
			{
				// Now do texture samples from our diffuse map with each of the 3 UV set's we've just made.
				half yDiff = tex2D(_TriplanarMap, WorldBasedUVs.xz).r;
				half zDiff = tex2D(_TriplanarMap, WorldBasedUVs.xy).r;
				half xDiff = tex2D(_TriplanarMap, WorldBasedUVs.zy).r;

				// Compromise: done in the vertex shader instead; difference shouldn't be noticeable in this project
				//half3 blendWeights = pow(abs(WorldNormal), TriplanarBlendSharpness);
				half3 blendWeights = AbsWorldNormal;

				// Divide our blend mask by the sum of it's components, this will make x+y+z=1
				//blendWeights = blendWeights / (blendWeights.x + blendWeights.y + blendWeights.z);
				half sum = dot(blendWeights, half3(1, 1, 1));
				blendWeights = blendWeights / sum;

				// No longer using half3 for the several texture reads, so this saves some instructions
				half col = dot(blendWeights, half3(xDiff, yDiff, zDiff));

				return col;
			}


			half4 BlendTriplanar(half3 SurfaceColour, half TriplanarColour, half ClippingHeight)
			{
				// The compiler seems to convert this automatically to dot(TriplanarColour, fixed3(0.3, 0.59, 0.11))
				//half luminance = TriplanarColour.r * 0.3 + TriplanarColour.g * 0.59 + TriplanarColour.b * 0.11;
				// Actually, it doesn't seem to make any difference between the code above and just picking the first component
				half luminance = TriplanarColour;
				half3 innerGradientColour = lerp(_GridTintEnd, _GridTint, luminance);

				half blendAmount = ClippingHeight / _TriplanarWidth;
				half3 gradientColour = lerp(_GridTint, innerGradientColour, saturate(blendAmount * 1.3));

				//half3 effectedSurfaceColour = SurfaceColour + _GridTintEnd * (1 - saturate(blendAmount * .7));
				half3 effectedSurfaceColour = lerp(_GridTintEnd, half3(0, 0, 0), saturate(blendAmount * .7));

				half surfaceAmount = saturate((luminance - blendAmount) * 20);
				//half3 finalColour = lerp(gradientColour, effectedSurfaceColour, 1 - surfaceAmount);
				half3 finalColour = lerp(SurfaceColour + effectedSurfaceColour, gradientColour, surfaceAmount);

				return half4(finalColour, 1);
			}


			// ---------------------------------------
			// VERTEX SHADER
			// ----------------------------------------
			v2f vert(appdata v)
			{
				UNITY_SETUP_INSTANCE_ID(v);

				v2f o;

				o.vertex = UnityObjectToClipPos(v.vertex);

				// switch to local space; world space has additional requirements/needs on object rotation
				//o.posWorld = mul(unity_ObjectToWorld, v.vertex).xyz;
				o.scaledWorldPosAndClippingHeight = v.vertex;
				o.scaledWorldPosAndClippingHeight.xyz /= _TriplanarMapScale;
				o.scaledWorldPosAndClippingHeight.w = _ClipAbove - v.vertex.y;

				o.height = mul(unity_ObjectToWorld, v.vertex).y;

				o.normalObj = (v.normal);
				o.uv = v.uv;

				// o.color = length(v.color) < 0.0001 ? 1.0 : v.color;
				// NOTE: Currently no vertex color is being used
				// o.color = v.color;

				float3 viewDir = WorldSpaceViewDir(v.vertex).xyz;
				float3 normalWorld = UnityObjectToWorldNormal(v.normal);
				o.reflectionAndExpNDotV.xyz = reflect(-viewDir, normalWorld);
				o.reflectionAndExpNDotV.w = dot(normalWorld, normalize(viewDir));
				o.premNDotV = 1 - o.reflectionAndExpNDotV.w;
				o.premNDotV = pow(o.premNDotV, _BorderThinness);
				o.reflectionAndExpNDotV.w = exp2(-9.28 * o.reflectionAndExpNDotV.w);


				UNITY_INITIALIZE_VERTEX_OUTPUT_STEREO(o);
				return o;
			}


			// ---------------------------------------
			// FRAGMENT SHADER
			// ---------------------------------------
			half4 frag(v2f i) : SV_Target
			{
				clip(i.scaledWorldPosAndClippingHeight.w);

				half4 col = _Color;
				half triplanarCol = CalculateTriplanar(i.scaledWorldPosAndClippingHeight.xyz, abs(i.normalObj));

				// NOTE: Currently no vertex color is being used, defaulting to black
				//col *= saturate((dot(_WorldSpaceLightPos0, i.normalObj) + 1) / 2);

				// Scanlines
				col = BlendTriplanar(col.rgb, triplanarCol, i.scaledWorldPosAndClippingHeight.w);
				
				col = col * lerp(fixed4(1, 1, 1, 1), _ScanlineTint, sin(_Time[3] * _ScanlineSpeed + i.height * _ScanlineWidth));
				col.a *= i.premNDotV *saturate(sin(_Time[3] * 1.5) / 3 + 0.75);

#if defined(_USE_OVERLAY)
				return _OverlayColor;// *_OverlayColor.a + col;
#else
				return _OverlayColor * _OverlayColor.a + col;
				return col;
#endif
			}
			ENDCG
        }
    }
}
