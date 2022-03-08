// Upgrade NOTE: replaced '_Object2World' with 'unity_ObjectToWorld'

Shader "HPScitex/FloorPlanShader"
{
	Properties
	{
		[PerRendererData] _MainTex ("Sprite Texture", 2D) = "white" {}
		
		_MainTint ("Main Tint", Color) = (1,1,1,1)
		_MainTintEdge ("Main Tint Edge", Color) = (1,1,1,1)
		_GridTexture ("GridTexture (R)", 2D) = "white" {}
		_GridScale ("GridScale", Float) = 1
		_GridTint ("Grid Tint", Color) = (1,1,1,1)
		_GridTintEnd ("Grid Tint End", Color) = (1,1,1,1)
		_GridTintEdge("Grid Tint Edge", Color) = (1,1,1,1)
		[PerRendererData] _Radius ("Radius", Float) = 10
		_WidthOuter ("Width Outer", Float) = 1
		_WidthInner ("Width Inner", Float) = 2
		_DistanceScale ("Distance Scale", Float) = 0
		_PulseTint("Pulse Tint", Color) = (1,1,1,1)
		_PulseFrequency("Pulse Frequency", Float) = 1
		_PulseWaveSpeed("Pulse Wave Speed", Float) = 1

		[PerRendererData] _InvFade("Inv Fade", Range(0,1)) = 0
		[PerRendererData] [Toggle(_USE_OVERLAY)] _UseOverlay("Use Overlay", Float) = 1.0
		[PerRendererData] [Toggle(_USE_GAZE_MASK)] _UseGazeMask("Use Gaze Mask", Float) = 1.0
		[PerRendererData] _OverlayColor("Overlay Color", Color) = (0, 1, 0.5, 0.5)
	}

	SubShader
	{
		Tags { "Queue" = "Transparent" }
		Zwrite Off
        ZTest [unity_GUIZTestMode]
		Blend One One
		Offset -1, 1
		LOD 100
		Cull Off

		Pass
		{
			CGPROGRAM
			#pragma vertex vert
			#pragma fragment frag
			#pragma target 5.0
			#pragma only_renderers d3d11
			#pragma shader_feature _USE_OVERLAY

			#include "UnityCG.cginc"

			struct appdata
			{
				float4 vertex : POSITION;
				float2 uv : TEXCOORD0;
				UNITY_VERTEX_INPUT_INSTANCE_ID
			};

			struct v2f
			{
				float2 uv : TEXCOORD0;
				float4 vertex : SV_POSITION;
				float3 posWorld : TEXCOORD1;
				float3 posObj : TEXCOORD2;
				UNITY_VERTEX_OUTPUT_STEREO
			};

			
			sampler2D _MainTex, _GridTexture;
			float4 _MainTex_ST;
			fixed4 _MainTint, _MainTintEdge, _GridTint, _GridTintEnd, _GridTintEdge, _PulseTint;
			float _WidthOuter, _WidthInner, _GridScale, _DistanceScale, _PulseFrequency, _PulseWaveSpeed;
			uniform float _Radius, _InvFade;
			float3 _PlacementCornerOrigin;
			float _OverlayRadius;
			fixed4 _OverlayColor;

			
			v2f vert (appdata v)
			{
				UNITY_SETUP_INSTANCE_ID(v);

				v2f o;
				o.vertex = UnityObjectToClipPos(v.vertex);
				o.posWorld = mul(unity_ObjectToWorld, v.vertex);
				o.posObj = v.vertex;
				o.uv = TRANSFORM_TEX(v.uv, _MainTex);

				UNITY_INITIALIZE_VERTEX_OUTPUT_STEREO(o);

				return o;
			}
			
			fixed4 frag (v2f i) : SV_Target
			{
				// sample the texture
				fixed4 mainTex = tex2D(_MainTex, i.uv);
				fixed alpha = mainTex.a;

				// get the distance from the point
				fixed2 distance = length(_PlacementCornerOrigin.xz - i.posWorld.xz);
				fixed gradientInner = 1 - smoothstep(distance, _Radius, _Radius - (_WidthInner + (_Radius * _DistanceScale * _WidthInner)));
				fixed gradientInnerEdge = 1 - smoothstep(distance, _Radius, _Radius - (_WidthInner / 3 + (_Radius * _DistanceScale * (_WidthInner / 3))));
				fixed gradientSolid = 1 - smoothstep(distance, _Radius, 0);
				fixed gradientOuter = 1 - smoothstep(_Radius, _Radius + (_WidthOuter + (_Radius * _DistanceScale * _WidthOuter)), distance) - gradientSolid;
				fixed gradientGrid = saturate(gradientInner + gradientOuter);
				fixed gradientMain = saturate(gradientSolid + gradientOuter);
				fixed gradientEdge = saturate(gradientInnerEdge + gradientOuter);

				// Get the colours
				fixed4 mainCol = mainTex * lerp(_MainTint, _MainTintEdge, gradientEdge) * alpha * gradientMain;

				fixed gradientGridModified = 1 - smoothstep(.1 , 2.2 , gradientGrid) * alpha;

				//half MainTexLuminance = mainCol.r * 0.3 + mainCol.g * 0.59 + mainCol.b * 0.11;
				fixed MainTexLuminance = mainCol.r;
				fixed4 pulseCol = (sin(((i.posObj.y - (i.posObj.x * .5)) + _Time.y * _PulseWaveSpeed) * _PulseFrequency) + .5) * _PulseTint * MainTexLuminance;

				// ExpandingGrid
				fixed4 gridTex = tex2D(_GridTexture, i.posObj.xy * _GridScale);
				// Grid only needs one color
				fixed luminance = gridTex.r;// *0.3 + gridTex.g * 0.59 + gridTex.b * 0.11;
				fixed surfaceAmount = saturate((luminance - gradientGridModified) * 20);

				fixed3 innerGradientColour = lerp(_GridTintEnd, _GridTint, luminance);
				fixed3 gridColourEdged = lerp(innerGradientColour, _GridTintEdge, gradientEdge);
				fixed3 gradientColour = lerp(_GridTint, gridColourEdged, saturate(gradientGridModified * 1.3));
#if defined(_USE_OVERLAY)
				mainCol.rgb += _OverlayColor.rgb * mainCol.r * 5;
#endif

				mainCol.rgb = mainCol.rgb + gradientColour * surfaceAmount + pulseCol.rgb;
				mainCol.a = alpha;

				return lerp(fixed4(0, 0, 0, 0), saturate(mainCol), saturate(_InvFade));

			}
			ENDCG
		}
	}
}
