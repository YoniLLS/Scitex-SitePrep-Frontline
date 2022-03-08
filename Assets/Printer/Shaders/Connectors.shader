Shader "Custom/Mannequin"
{
    Properties
    {
		_Color("Color", Color) = (0,0,0,1)

		// Scanlines
		[Space(10)]
		_ScanlineTint("Scanline Tint", Color) = (0.25, 0.25, 0.25, 1)
		_ScanlineWidth("Scanline Width", Float) = 1
		_ScanlineSpeed("Scanline Speed", Float) = 1

		_SpreadInside("Spread inside", Float) = 1.0
    }

    SubShader
    {
        Tags { "RenderType"="Opaque" }
        LOD 100



		Pass
		{
			ZWrite Off
			Cull Off
			ZTest GEqual
			Blend SrcAlpha One

			CGPROGRAM
			#pragma vertex vert
			#pragma fragment frag
			#pragma target 5.0
			#pragma only_renderers d3d11

			#include "UnityCG.cginc"
			#include "UnityStandardConfig.cginc"

			struct appdata
			{
				float4 vertex : POSITION;
				UNITY_VERTEX_INPUT_INSTANCE_ID
			};


			struct v2f
			{
				half4 vertex : SV_POSITION;
				UNITY_VERTEX_OUTPUT_STEREO
			};

			half4 _Color;
			half4 _ScanlineTint;
			half _SpreadInside;

			v2f vert(appdata v)
			{
				UNITY_SETUP_INSTANCE_ID(v);

				v2f o;

				o.vertex = UnityObjectToClipPos(v.vertex);
				
				UNITY_INITIALIZE_VERTEX_OUTPUT_STEREO(o);
				return o;
			}


			// ---------------------------------------
			// FRAGMENT SHADER
			// ---------------------------------------
			half4 frag(v2f i) : SV_Target
			{
				half4 col = _ScanlineTint;
				col.a = 0.5 * _Color.a;
				return col;
			}
			ENDCG
		}

        Pass
        {
			Blend SrcAlpha One
			ZWrite On
			ZTest Less
			Cull Off

			CGPROGRAM
			#pragma vertex vert
			#pragma fragment frag
			#pragma target 5.0
			#pragma only_renderers d3d11

			#include "UnityCG.cginc"
			#include "UnityStandardConfig.cginc"

			struct appdata
			{
				float4 vertex : POSITION;
				float3 normal : NORMAL;
				float4 color : COLOR;
				UNITY_VERTEX_INPUT_INSTANCE_ID
			};


			struct v2f
			{
				half4 vertex : SV_POSITION;
				half premNDotV : TEXCOORD3;
				half height : TEXCOORD4;
				UNITY_VERTEX_OUTPUT_STEREO
			};


			half4 _Color;
			half4 _ScanlineTint;
			half _ScanlineSpeed, _ScanlineWidth;
			half _SpreadInside;



			// ---------------------------------------
			// VERTEX SHADER
			// ----------------------------------------
			v2f vert(appdata v)
			{
				UNITY_SETUP_INSTANCE_ID(v);

				v2f o;

				o.vertex = UnityObjectToClipPos(v.vertex);
				o.height = mul(unity_ObjectToWorld, v.vertex).y;

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
				half4 col = _Color;

				// Scanlines
				col = col * lerp(fixed4(1, 1, 1, 1), _ScanlineTint, sin(_Time[3] * _ScanlineSpeed + i.height * _ScanlineWidth));
				col.a *= i.premNDotV *saturate(sin(_Time[3] * 1.5) / 3 + 0.75);

				return col;
			}
			ENDCG
        }

    }
}
