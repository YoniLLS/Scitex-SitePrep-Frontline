Shader "Custom/DistanceArea"
{
    Properties
    {
        _MainTex ("Texture", 2D) = "white" {}
		_Color("Color", Color) = (1, 1, 1, 1)
		[PerRendererData] _TintColor("Tint Color", Color) = (1, 1, 1, 1)

		[Toggle(_USE_SPOTLIGHT)] _UseSpotlight("Use Spotlight", Float) = 1.0
		[Toggle(_USE_OUTLINE)] _UseOutline("Use Outline", Float) = 1.0
		_OutlineWidth("Outline Width", Float) = 1.0
			
		_WorldPosRadius("World position (xyz) Radius (w)", Vector) = (0, 0, 0, 0)
    }
    SubShader
    {
        Tags { "RenderType"="Opaque" }
        LOD 100

        Pass
        {
			Blend SrcAlpha OneMinusSrcAlpha

            CGPROGRAM
            #pragma vertex vert
            #pragma fragment frag
			#pragma shader_feature _USE_SPOTLIGHT
			#pragma shader_feature _USE_OUTLINE

            #include "UnityCG.cginc"

            struct appdata
            {
                float4 vertex : POSITION;
                float2 uv : TEXCOORD0;
				UNITY_VERTEX_INPUT_INSTANCE_ID
            };

            struct v2f
            {
				// original uvs = uvSets.xy, world uvs = uvSets.zw
                float4 uvSets : TEXCOORD1;
                float4 vertex : SV_POSITION;
				float4 worldPos : TEXCOORD2;

				UNITY_VERTEX_OUTPUT_STEREO
            };

            sampler2D _MainTex;
			float4 _MainTex_ST;
			fixed4 _Color;
			fixed4 _TintColor;
			float4 _WorldPosRadius;
			fixed _OutlineWidth;


            v2f vert (appdata v)
            {
				UNITY_SETUP_INSTANCE_ID(v);
                v2f o;

				o.vertex = UnityObjectToClipPos(v.vertex);

				// xy = original uvs
				o.uvSets.xy = v.uv;
				// zw = world space floor (XZ plane) position-based uvs
				o.uvSets.zw = mul(unity_ObjectToWorld, v.vertex).xz;
				o.uvSets.zw = TRANSFORM_TEX(o.uvSets.zw, _MainTex);

				o.worldPos = mul(unity_ObjectToWorld, v.vertex);
				o.worldPos.y = _WorldPosRadius.y;
				// world position.w = inverse of the object scale factor (may not work with non-uniform scale)
				o.worldPos.w = 1.0 / unity_ObjectToWorld[0].x;

				UNITY_INITIALIZE_VERTEX_OUTPUT_STEREO(o);

                return o;
            }


            fixed4 frag (v2f i) : SV_Target
            {
                // Sample the texture
				fixed4 col = tex2D(_MainTex, frac(i.uvSets.zw)) *_Color;

				float value = 1.0f;
#if defined (_USE_SPOTLIGHT)
				// Radius with higher alpha to create a "spotlight" effect and avoid saturating a bigger area
				// Using trunc to create a sharp cutout
				value = trunc(1 + _WorldPosRadius.w - distance(i.worldPos.xyz, _WorldPosRadius.xyz));
				col.a = lerp(col.a * 0.1, col.a, saturate(value));
#endif

#if defined (_USE_OUTLINE)
				// Create the border around the area
				// worldPos.w is the inverse of the (uniform) scale factor
				value = trunc(max(i.uvSets.x, i.uvSets.y) + _OutlineWidth * i.worldPos.w);

				fixed4 outlineColor = _Color;
				outlineColor.rgb *= _TintColor.rgb;
				col = lerp(col, outlineColor, saturate(value));
#endif
				col.rgb *= _TintColor.rgb;
                return col;
            }
            ENDCG
        }
    }
}
