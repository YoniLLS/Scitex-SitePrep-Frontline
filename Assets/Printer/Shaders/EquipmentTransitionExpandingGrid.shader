Shader "HPScitex/Equipment Transition Expanding Grid"
{
	Properties
	{
		_LightingMultiplier("Lighting Multiplier", Float) = 1
		_MainTex("Main Texture", 2D) = "white" {}
		_Roughness("Roughness", Range(0.0, 1.0)) = 0.25
		_RoughnessMin("Roughness Min", Range(0.0, 1.0)) = 0

		_ClipAbove("Clip above", Float) = 6.0
		// NOTE: Not used in the current version; must have been left here while prototyping
		// It is never modified at runtime currently, although the script "MaterialTransition"
		// could modify it, but it is not in used in the current build
		//_TriplanarBlend("Blend", Range(0.0, 1.0)) = 0.0

		// We are using this texture as a mask, so one channel is enough
		_TriplanarMap("Triplanar Texture (R)", 2D) = "white" {}
		_TriplanarMapScale("Scale", Range(0.0, 10.0)) = 0.5
		_TriplanarWidth("Triplanar width", Float) = 2.5

		_GridTint("Grid Tint", Color) = (1,1,1,1)
		_GridTintEnd("Grid Tint End", Color) = (1,1,1,1)

		[Enum(UnityEngine.Rendering.CompareFunction)] _ZTest("Z Test", Float) = 4
		[Enum(UnityEngine.Rendering.BlendMode)] _SrcBlend("Src Blend", Int) = 5.0
		[Enum(UnityEngine.Rendering.BlendMode)] _DstBlend("Dst Blend", Int) = 10.0
	}
	SubShader
	{
		Tags { "RenderType"="Opaque" }
		
		Pass
		{
			Cull Front
			Blend[_SrcBlend][_DstBlend]

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
				float2 uv : TEXCOORD0;
				UNITY_VERTEX_INPUT_INSTANCE_ID
			};


			struct v2f
			{
				half4 vertex : SV_POSITION;
				half3 uvAndClippingHeight : TEXCOORD0;
				UNITY_VERTEX_OUTPUT_STEREO
			};

			half _ClipAbove;
			fixed4 _GridTint;
			sampler2D _MainTex;

			v2f vert (appdata v)
			{
				UNITY_SETUP_INSTANCE_ID(v);

				v2f o;
				
				o.vertex = UnityObjectToClipPos(v.vertex);
				o.uvAndClippingHeight.xy = v.uv;

				// switch to local space; world space has additional requirements/needs on object rotation
				//o.posWorld = mul(unity_ObjectToWorld, v.vertex).xyz;
				o.uvAndClippingHeight.z = _ClipAbove - v.vertex.y;

				UNITY_INITIALIZE_VERTEX_OUTPUT_STEREO(o);
				return o;
			}
			

			// ---------------------------------------
			// FRAGMENT SHADER
			// ---------------------------------------
			half4 frag (v2f i) : SV_Target
			{
				clip(i.uvAndClippingHeight.z);

				half4 col = tex2D(_MainTex, i.uvAndClippingHeight.xy);
				col.rgb = _GridTint.rgb;
				return col;
			}
			ENDCG
		}
		

		Pass
		{
			// This pass seems to have been based on this one:
			// www.martinpalko.com/triplanar-mapping/
			// The pass has been further refined to be optimized to the specific use case of this project
			Cull Back
			Blend [_SrcBlend] [_DstBlend]

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
				float2 uv : TEXCOORD0;
				float4 color : COLOR;
				UNITY_VERTEX_INPUT_INSTANCE_ID
			};


			struct v2f
			{
				half4 vertex : SV_POSITION;
				half3 absNormalObj : NORMAL;
				//half4 color : COLOR;
				half2 uv : TEXCOORD0;
				/// xyz = localPos.pos.xyz / _TriplanarMapScale, w = localPos.y
				half4 scaledWorldPosAndClippingHeight : TEXCOORD1;
				/// xyz = reflection, w = exp2(-9.28 * nDotV)
				half4 reflectionAndExpNDotV : TEXCOORD2;
				UNITY_VERTEX_OUTPUT_STEREO
			};


			sampler2D _MainTex;
			sampler2D _TriplanarMap;
			half4 _GridTint, _GridTintEnd;
			half _Roughness, _RoughnessMin, _TriplanarMapScale;
			half _TriplanarWidth, _LightingMultiplier;
			half _ClipAbove;


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
				half sum = dot(blendWeights, fixed3(1, 1, 1));
				blendWeights = blendWeights / sum;

				// Finally, blend together all three samples based on the blend mask.
				//half col = xDiff * blendWeights.x + yDiff * blendWeights.y + zDiff * blendWeights.z;
				// No longer using half3 for the several texture reads, so this saves some instructions
				half col = dot(blendWeights, fixed3(xDiff, yDiff, zDiff));

				return col;
			}


			inline half CalculateBRDF(half Roughness, half nDotV)
			{
				const half4 c0 = half4(-1, -0.0275, -0.572, 0.022);
				const half4 c1 = half4(1, 0.0425, 1.04, -0.04);
				half4 r = (Roughness * c0) + c1;
				//half a004 = min(r.x * r.x, exp2(-9.28 * nDotV)) * r.x + r.y;
				// nDotV already premultiplied in vertex shader
				half a004 = min(r.x * r.x, nDotV) * r.x + r.y;
				//half2 AB = half2(-1.04, 1.04) * a004 + r.zw;
				half AB = 1.04 * a004 + r.w;

				//return AB.y;
				return AB;
			}


			half3 CalculateSurface(half3 reflection, half nDotV, half Roughness, half4 tex)
			{
				// half ao = (tex.a * 0.9) + 0.1;
				half ao = 1;

				half4 radiancePacked = UNITY_SAMPLE_TEXCUBE_LOD(unity_SpecCube0, reflection, Roughness * UNITY_SPECCUBE_LOD_STEPS);
				half3 radiance = radiancePacked.xyz * radiancePacked.w * _LightingMultiplier;

				half brdf = CalculateBRDF(Roughness, nDotV);

				//half3 col = lerp(tex.rgb * radiance * ao, radiance, brdf);
				half3 col = radiance * lerp(tex.rgb * ao, 1, brdf);
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
			v2f vert (appdata v)
			{
				UNITY_SETUP_INSTANCE_ID(v);

				v2f o;
				
				o.vertex = UnityObjectToClipPos(v.vertex);

				// switch to local space; world space has additional requirements/needs on object rotation
				//o.posWorld = mul(unity_ObjectToWorld, v.vertex).xyz;
				o.scaledWorldPosAndClippingHeight = v.vertex;
				o.scaledWorldPosAndClippingHeight.xyz /= _TriplanarMapScale;
				o.scaledWorldPosAndClippingHeight.w = _ClipAbove - v.vertex.y;
			
				o.absNormalObj = abs(v.normal);
				o.uv = v.uv;

				// o.color = length(v.color) < 0.0001 ? 1.0 : v.color;
				// NOTE: Currently no vertex color is being used
				// o.color = v.color;

				float3 viewDir = WorldSpaceViewDir(v.vertex).xyz;
				float3 normalWorld = UnityObjectToWorldNormal(v.normal);
				o.reflectionAndExpNDotV.xyz = reflect(-viewDir, normalWorld);
				o.reflectionAndExpNDotV.w = dot(normalWorld, normalize(viewDir));
				// See CalculateBRDF: operation moved from fragment to vertex shader
				o.reflectionAndExpNDotV.w = exp2(-9.28 * o.reflectionAndExpNDotV.w);

				UNITY_INITIALIZE_VERTEX_OUTPUT_STEREO(o);
				return o;
			}
			

			// ---------------------------------------
			// FRAGMENT SHADER
			// ---------------------------------------
			half4 frag (v2f i) : SV_Target
			{
				clip(i.scaledWorldPosAndClippingHeight.w);

				half4 col = tex2D(_MainTex, i.uv);
				if (col.a < 0.1)
				{
					discard;
				}

				half triplanarCol = CalculateTriplanar(i.scaledWorldPosAndClippingHeight.xyz, i.absNormalObj);

				// NOTE: Currently no vertex color is being used, defaulting to black
				//half roughness = lerp(_RoughnessMin, _Roughness, 1 - i.color.r);
				half roughness = _Roughness;
				col.rgb = CalculateSurface(i.reflectionAndExpNDotV.xyz, i.reflectionAndExpNDotV.w, roughness, col);
				col = BlendTriplanar(col.rgb, triplanarCol, i.scaledWorldPosAndClippingHeight.w);

				//col.rgb = triplanarCol;
				return col;
			}
			ENDCG
		}
	}
}
