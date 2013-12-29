/**
 * Defines Texture, which contains info for a texture loaded into the world.
 */
module components.texture;
import core.properties;
import components.icomponent;
import graphics.graphics, graphics.shaders.ishader;

import derelict.opengl3.gl3;
import derelict.freeimage.freeimage;

class Texture : IComponent
{
public:
	mixin( Property!( "uint", "width" ) );
	mixin( Property!( "uint", "height" ) );

	this( string filePath )
	{	
		super( null );

		if( Graphics.activeAdapter == GraphicsAdapter.OpenGL )
		{
			DerelictFI.load();

			FIBITMAP* imageData = FreeImage_ConvertTo32Bits( FreeImage_Load( FreeImage_GetFileType( filePath.ptr, 0 ), filePath.ptr, 0 ) );

			width = FreeImage_GetWidth( imageData );
			height = FreeImage_GetHeight( imageData );

			glGenTextures( 1, &_glId );
			glBindTexture( GL_TEXTURE_2D, glId );
			glTexImage2D(
				GL_TEXTURE_2D,
				0,
				GL_RGBA,
				width,
				height,
				0,
				GL_BGRA,
				GL_UNSIGNED_BYTE,
				cast(GLvoid*)FreeImage_GetBits( imageData ) );
			glTexParameteri( GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_NEAREST );

			FreeImage_Unload( imageData );
			glBindTexture( GL_TEXTURE_2D, 0 );
		}
		version( Windows )
		if( Graphics.activeAdapter == GraphicsAdapter.DirectX )
		{
			
		}
	}

	override void update()
	{

	}

	override void draw( IShader shader )
	{
		shader.bindTexture( this );
	}

	override void shutdown()
	{
		if( Graphics.activeAdapter == GraphicsAdapter.OpenGL )
		{
			glBindTexture( GL_TEXTURE_2D, 0 );
			glDeleteBuffers( 1, &_glId );
		}
		version( Windows )
		if( Graphics.activeAdapter == GraphicsAdapter.DirectX )
		{

		}
	}

	mixin( BackedProperty!( "uint", "_glId", "glId" ) );

	union
	{
		uint _glId;
	}
}