Shader "Custom/Door Volume Shader"
{
	Properties
	{
		_Color ("Color", Color) = (1, 1, 1, 1)
		_FadeSpread("Fade spread", Float) = 0
		_BorderColor("Border Color", Color) = (1, 1, 1, 1)
		_BorderWidth("Border width", Float) = 0.1
	}


	SubShader
	{
		Tags { "RenderType"="Opaque" }
		LOD 100

		Pass
		{
			Cull Off
			Blend SrcAlpha One
			ZWrite Off

			CGPROGRAM
			#pragma vertex vert
			#pragma fragment frag
		// make fog work
		#pragma multi_compile_fog

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
			UNITY_VERTEX_OUTPUT_STEREO
		};

		uniform float4 _Color;
		uniform float4 _BorderColor;
		uniform fixed _BorderWidth;
		uniform fixed _FadeSpread;

		v2f vert(appdata v)
		{
			UNITY_SETUP_INSTANCE_ID(v);

			v2f o;
			o.vertex = UnityObjectToClipPos(v.vertex);
			o.uv = float2(1, 1) - v.uv;

			UNITY_INITIALIZE_VERTEX_OUTPUT_STEREO(o);

			return o;
		}

		fixed4 frag(v2f i) : SV_Target
		{
			// sample the texture
			fixed4 col = _Color;
			col.a *= saturate(i.uv.x + _FadeSpread);

			col = lerp(col, _BorderColor, step(i.uv.x, _BorderWidth));
			return col;
		}
		ENDCG
	}

	}
}
