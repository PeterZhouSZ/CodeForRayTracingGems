//
// Ray Tracing Gems sample code for 
//   "A Planetarium Dome Master Camera"
// 
// This code is a simplified derivative of the 
// C- and CUDA-based implementations in 
// the Tachyon ray tracing engine and the 
// VMD molecular visualization software.
// 
// Questions should be directed to the author
// John E. Stone, developer of Tachyon and VMD
//

#include "boilerplate.cuh"

//
// Camera ray generation code for planetarium dome display
// Generates a fisheye style frame with ~180 degree FoV
//
template<int STEREO_ON, int DOF_ON>
static __device__ __inline__
void camera_dome_general() {
  // Stereoscopic rendering is provided by rendering in an over/under
  // format with the left eye image into the top half of a double-high
  // framebuffer, and the right eye into the lower half.  The subsequent
  // OpenGL drawing code can trivially unpack and draw the two images
  // with simple pointer offset arithmetic.
  uint viewport_sz_y, viewport_idx_y;
  float eyeshift;
  if (STEREO_ON) {
    // render into a double-high framebuffer when stereo is enabled
    viewport_sz_y = launch_dim.y >> 1;
    if (launch_index.y >= viewport_sz_y) {
      // left image
      viewport_idx_y = launch_index.y - viewport_sz_y;
      eyeshift = -0.5f * cam_stereo_eyesep;
    } else {
      // right image
      viewport_idx_y = launch_index.y;
      eyeshift =  0.5f * cam_stereo_eyesep;
    }
  } else {
    // render into a normal size framebuffer if stereo is not enabled
    viewport_sz_y = launch_dim.y;
    viewport_idx_y = launch_index.y;
    eyeshift = 0.0f;
  }

  float fov = 180.0f;                          // dome FoV in degrees

  // half FoV in radians, pixels beyond this distance are outside
  // of the field of view of the projection, and are set black
  float rmax = 0.5 * fov * (M_PIf / 180.0f);

  // The dome angle from center of the projection is proportional
  // to the image-space distance from the center of the viewport.
  // viewport_sz contains the viewport size, radperpix contains the
  // radians/pixel scaling factors in X/Y, and viewport_mid contains
  // the midpoint coordinate of the viewpoint used to compute the
  // distance from center.
  float2 viewport_sz = make_float2(launch_dim.x, viewport_sz_y);
  float2 radperpix = (M_PIf / 180.0f) * fov / viewport_sz;
  float2 viewport_mid = viewport_sz * 0.5f;

  unsigned int randseed = tea<4>(launch_dim.x*(launch_index.y)+launch_index.x, subframe_count());

  float3 col = make_float3(0.0f);
  float alpha = 0.0f;
  for (int s=0; s<aa_samples; s++) {
    // compute the jittered image plane sample coordinate
    float2 jxy;
    jitter_offset2f(randseed, jxy);
    float2 viewport_idx = make_float2(launch_index.x, viewport_idx_y) + jxy;

    // compute the ray angles in X/Y and total angular distance from center
    float2 rd = (viewport_idx - viewport_mid) * radperpix;
    float rangle = hypotf(rd.x, rd.y);

    // pixels outside the dome FoV are treated as black by not
    // contributing to the color accumulator
    if (rangle < rmax) {
      float3 ray_direction;
      float3 ray_origin = cam_pos;

      if (rangle == 0) {
        // handle center of dome where azimuth is undefined by
        // setting the ray direction to the zenith
        ray_direction = cam_W;
      } else {
        float rasin, racos;
        sincosf(rangle, &rasin, &racos);
        float rsin = rasin / rangle;
        float rcos = racos / rangle;
        ray_direction = cam_U*rsin*rd.x + cam_V*rsin*rd.y + cam_W*racos;
        up_direction = -cam_U*rcos*rd.x - cam_V*rcos*rd.y + cam_W*rasin;
        right_direction = cam_U*(rd.y/rangle) + cam_V*(-rd.x/rangle);

        if (STEREO_ON) {
          // assumes a flat dome, where cam_W also points in the 
          // audience "up" direction
          ray_origin += eyeshift * powf(cross(ray_direction, cam_W), 5.0);
        }

        if (DOF_ON) {
          dof_ray(ray_origin, ray_origin, ray_direction, ray_direction,
                  randseed, up_direction, right_direction);
        }
      }

      // trace the new ray...
      PerRayData_radiance prd;
      prd.importance = 1.f;
      prd.alpha = 1.f;
      prd.depth = 0;
      prd.transcnt = max_trans;
      optix::Ray ray = optix::make_Ray(ray_origin, ray_direction, radiance_ray_type, scene_epsilon, RT_DEFAULT_MAX);
      rtTrace(root_object, ray, prd);
      col += prd.result;
      alpha += prd.alpha;
    }
  }

  accumulate_color(col, alpha);
}


//
// Template instantiations to create optimized
// case-specific versions of the raygen program.
//
RT_PROGRAM void camera_dome_master() {
  camera_dome_general<0, 0>();
}

RT_PROGRAM void camera_dome_master_dof() {
  camera_dome_general<0, 1>();
}

RT_PROGRAM void camera_dome_master_stereo() {
  camera_dome_general<1, 0>();
}

RT_PROGRAM void camera_dome_master_stereo_dof() {
  camera_dome_general<1, 1>();
}



