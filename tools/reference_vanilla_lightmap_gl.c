/* Reference-only execution of the installed shader, on an offscreen CGL FBO.
   Never creates an NSWindow or changes the foreground app. */
#define GL_SILENCE_DEPRECATION
#include <OpenGL/OpenGL.h>
#include <OpenGL/gl3.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
static void fail(const char *s){fprintf(stderr,"%s\n",s);exit(2);}
static char *read_file(const char *p){FILE*f=fopen(p,"rb");if(!f)fail("shader read");fseek(f,0,SEEK_END);long n=ftell(f);rewind(f);char*s=calloc(n+1,1);if(fread(s,1,n,f)!=(size_t)n)fail("shader bytes");fclose(f);return s;}
static GLuint shader(GLenum kind,const char*s){GLuint n=glCreateShader(kind);glShaderSource(n,1,&s,NULL);glCompileShader(n);GLint ok;glGetShaderiv(n,GL_COMPILE_STATUS,&ok);if(!ok){char log[4096];glGetShaderInfoLog(n,sizeof(log),NULL,log);fail(log);}return n;}
static GLuint program(const char *frag){
 const char*vert="#version 410\nlayout(location=0) out vec2 texCoord;void main(){vec2 p=vec2((gl_VertexID<<1)&2,gl_VertexID&2);texCoord=p;gl_Position=vec4(p*2.0-1.0,0.0,1.0);}";
 GLuint p=glCreateProgram(),v=shader(GL_VERTEX_SHADER,vert),f=shader(GL_FRAGMENT_SHADER,frag);glAttachShader(p,v);glAttachShader(p,f);glLinkProgram(p);GLint ok;glGetProgramiv(p,GL_LINK_STATUS,&ok);if(!ok){char log[4096];glGetProgramInfoLog(p,sizeof(log),NULL,log);fail(log);}glDeleteShader(v);glDeleteShader(f);return p;
}
int main(int argc,char**argv){
 if(argc!=4)fail("shader, sampler include and binary uniforms required");
 CGLPixelFormatAttribute a[]={kCGLPFAOpenGLProfile,(CGLPixelFormatAttribute)kCGLOGLPVersion_GL4_Core,kCGLPFAAccelerated,(CGLPixelFormatAttribute)0};
 CGLPixelFormatObj pix;GLint count;CGLContextObj ctx;
 if(CGLChoosePixelFormat(a,&pix,&count)||!count||CGLCreateContext(pix,NULL,&ctx)||CGLSetCurrentContext(ctx))fail("offscreen CGL context unavailable");CGLDestroyPixelFormat(pix);
 char*source=read_file(argv[1]);GLuint p=program(source);free(source);
 char*include=read_file(argv[2]);size_t sl=strlen(include)+512;char*sampling=malloc(sl);snprintf(sampling,sl,"#version 330\n%s\nuniform sampler2D lightMap;uniform ivec2 coordinates;layout(location=0) out vec4 fragColor;void main(){fragColor=sample_lightmap(lightMap,coordinates);}",include);GLuint sp=program(sampling);free(include);free(sampling);glUseProgram(p);
 GLuint vao,ubo,fb,texture;glGenVertexArrays(1,&vao);glBindVertexArray(vao);glGenBuffers(1,&ubo);glBindBuffer(GL_UNIFORM_BUFFER,ubo);
 GLint size;GLuint block=glGetUniformBlockIndex(p,"LightmapInfo");glGetActiveUniformBlockiv(p,block,GL_UNIFORM_BLOCK_DATA_SIZE,&size);if(size!=96)fail("unexpected LightmapInfo GPU layout");glUniformBlockBinding(p,block,0);glBindBufferBase(GL_UNIFORM_BUFFER,0,ubo);
 glGenFramebuffers(1,&fb);glBindFramebuffer(GL_FRAMEBUFFER,fb);glGenTextures(1,&texture);glBindTexture(GL_TEXTURE_2D,texture);glViewport(0,0,16,16);glDisable(GL_DITHER);glDisable(GL_FRAMEBUFFER_SRGB);
 GLuint target;glGenTextures(1,&target);glBindTexture(GL_TEXTURE_2D,target);glTexImage2D(GL_TEXTURE_2D,0,GL_RGBA32F,1,1,0,GL_RGBA,GL_FLOAT,NULL);glBindTexture(GL_TEXTURE_2D,texture);
 FILE*in=fopen(argv[3],"rb");if(!in)fail("uniform inputs");uint32_t n;if(fread(&n,4,1,in)!=1)fail("case count");
 printf("{\"backend\":\"%s\",\"version\":\"%s\",\"ubo_bytes\":%d,\"cases\":[",glGetString(GL_RENDERER),glGetString(GL_VERSION),size);
 for(uint32_t k=0;k<n;k++){
  float uniforms[24];if(fread(uniforms,sizeof(uniforms),1,in)!=1)fail("uniform data");glBufferData(GL_UNIFORM_BUFFER,sizeof(uniforms),uniforms,GL_STATIC_DRAW);glUseProgram(p);glBindTexture(GL_TEXTURE_2D,texture);glViewport(0,0,16,16);
  uint32_t raw[16*16*4];unsigned char bytes[16*16*4];
  glTexImage2D(GL_TEXTURE_2D,0,GL_RGBA32F,16,16,0,GL_RGBA,GL_FLOAT,NULL);glFramebufferTexture2D(GL_FRAMEBUFFER,GL_COLOR_ATTACHMENT0,GL_TEXTURE_2D,texture,0);if(glCheckFramebufferStatus(GL_FRAMEBUFFER)!=GL_FRAMEBUFFER_COMPLETE)fail("float FBO");glDrawArrays(GL_TRIANGLES,0,3);glReadPixels(0,0,16,16,GL_RGBA,GL_FLOAT,raw);
  glTexImage2D(GL_TEXTURE_2D,0,GL_RGBA8,16,16,0,GL_RGBA,GL_UNSIGNED_BYTE,NULL);glDrawArrays(GL_TRIANGLES,0,3);glReadPixels(0,0,16,16,GL_RGBA,GL_UNSIGNED_BYTE,bytes);if(glGetError()!=GL_NO_ERROR)fail("GL execution error");
  printf("%s{\"raw\":[",k?",":"");for(int i=0;i<256;i++)printf("%s[%u,%u,%u]",i?",":"",raw[4*i],raw[4*i+1],raw[4*i+2]);printf("],\"argb\":[");for(int i=0;i<256;i++)printf("%s%u",i?",":"",((uint32_t)bytes[4*i+3]<<24)|((uint32_t)bytes[4*i]<<16)|((uint32_t)bytes[4*i+1]<<8)|bytes[4*i+2]);printf("],\"samples\":[");
  glUseProgram(sp);glTexParameteri(GL_TEXTURE_2D,GL_TEXTURE_MIN_FILTER,GL_LINEAR);glTexParameteri(GL_TEXTURE_2D,GL_TEXTURE_MAG_FILTER,GL_LINEAR);glTexParameteri(GL_TEXTURE_2D,GL_TEXTURE_WRAP_S,GL_CLAMP_TO_EDGE);glTexParameteri(GL_TEXTURE_2D,GL_TEXTURE_WRAP_T,GL_CLAMP_TO_EDGE);glFramebufferTexture2D(GL_FRAMEBUFFER,GL_COLOR_ATTACHMENT0,GL_TEXTURE_2D,target,0);glViewport(0,0,1,1);
  uint32_t coords[]={0,1,15,16,17,65536,983055,7340153,8388736,15728880,4294967295};for(int i=0;i<11;i++){uint32_t sampled[4];glUniform2i(glGetUniformLocation(sp,"coordinates"),coords[i]&65535,coords[i]>>16);glDrawArrays(GL_TRIANGLES,0,3);glReadPixels(0,0,1,1,GL_RGBA,GL_FLOAT,sampled);printf("%s[%u,%u,%u]",i?",":"",sampled[0],sampled[1],sampled[2]);}printf("]}");
 }
 puts("]}");fclose(in);glDeleteTextures(1,&texture);glDeleteTextures(1,&target);glDeleteFramebuffers(1,&fb);glDeleteBuffers(1,&ubo);glDeleteVertexArrays(1,&vao);glDeleteProgram(p);glDeleteProgram(sp);CGLSetCurrentContext(NULL);CGLDestroyContext(ctx);return 0;
}
