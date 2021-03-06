/**
 * Defines the Material and Texture classes.
 */
module components.material;
import core, components, graphics, utility;

import yaml;
import derelict.opengl3.gl3, derelict.freeimage.freeimage;
import std.variant, std.conv, std.string;

/**
 * A collection of textures that serve different purposes in the rendering pipeline.
 */
shared final class Material
{
private:
    Texture _diffuse, _normal, _specular;

public:
    /// The diffuse (or color) map.
    mixin( Property!(_diffuse, AccessModifier.Public) );
    /// The normal map, which specifies which way a face is pointing at a given pixel.
    mixin( Property!(_normal, AccessModifier.Public) );
    /// The specular map, which specifies how shiny a given point is.
    mixin( Property!(_specular, AccessModifier.Public) );

    /**
     * Default constructor, makes sure everything is initialized to default.
     */
    this()
    {
        _diffuse = _normal = _specular = defaultTex;
    }

    /**
     * Create a Material from a Yaml node.
     *
     * Params:
     *  yamlObj =           The YAML object to pull the data from.
     *
     * Returns: A new material with specified maps.
     */
    static shared(Material) createFromYaml( Node yamlObj )
    {
        auto obj = new shared Material;
        string prop;

        if( Config.tryGet( "Diffuse", prop, yamlObj ) )
            obj.diffuse = Assets.get!Texture( prop );

        if( Config.tryGet( "Normal", prop, yamlObj ) )
            obj.normal = Assets.get!Texture( prop );

        if( Config.tryGet( "Specular", prop, yamlObj ) )
            obj.specular = Assets.get!Texture( prop );

        return obj;
    }
}

/**
 * TODO
 */
shared class Texture
{
protected:
    uint _width, _height, _glID;

    /**
     * TODO
     *
     * Params:
     *
     * Returns:
     */
    this( ubyte* buffer )
    {
        glGenTextures( 1, cast(uint*)&_glID );
        glBindTexture( GL_TEXTURE_2D, glID );
        updateBuffer( buffer );
    }

    /**
     * TODO
     *
     * Params:
     *
     * Returns:
     */
    void updateBuffer( const ubyte* buffer )
    {
        // Set texture to update
        glBindTexture( GL_TEXTURE_2D, glID );

        // Update texture
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
        glTexImage2D( GL_TEXTURE_2D, 0, GL_RGBA, _width, _height, 0, GL_BGRA, GL_UNSIGNED_BYTE, cast(GLvoid*)buffer );
        glTexParameteri( GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR );
    }

public:
    /// TODO
    mixin( Property!_width );
    /// TODO
    mixin( Property!_height );
    /// TODO
    mixin( Property!_glID );

    /**
     * TODO
     *
     * Params:
     *
     * Returns:
     */
    this( string filePath )
    {
        filePath ~= "\0";
        auto imageData = FreeImage_ConvertTo32Bits( FreeImage_Load( FreeImage_GetFileType( filePath.ptr, 0 ), filePath.ptr, 0 ) );

        width = FreeImage_GetWidth( imageData );
        height = FreeImage_GetHeight( imageData );

        this( cast(ubyte*)FreeImage_GetBits( imageData ) );

        FreeImage_Unload( imageData );
    }

    /**
     * TODO
     *
     * Params:
     *
     * Returns:
     */
    void shutdown()
    {
        glBindTexture( GL_TEXTURE_2D, 0 );
        glDeleteBuffers( 1, cast(uint*)&_glID );
    }
}

/**
 * TODO
 *
 * Params:
 *
 * Returns:
 */
@property shared(Texture) defaultTex()
{
    static shared Texture def;

    if( !def )
        def = new shared Texture( [0, 0, 0, 255] );

    return def;
}

static this()
{
    IComponent.initializers[ "Material" ] = ( Node yml, shared GameObject obj )
    {
        obj.material = Assets.get!Material( yml.get!string );
        return null;
    };
}
