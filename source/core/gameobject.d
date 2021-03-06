/**
 * Defines the GameObject class, to be subclassed by scripts and instantiated for static objects.
 */
module core.gameobject;
import core, components, graphics, utility;

import yaml;
import gl3n.linalg, gl3n.math;

import std.conv, std.variant, std.array;

enum AnonymousName = "__anonymous";

/**
 * Contains flags for all things that could be disabled.
 */
shared struct ObjectStateFlags
{
    bool update;
    bool updateChildren;
    bool drawMesh;
    bool drawLight;

    /**
     * Set each member to false.
     */
    void pauseAll()
    {
        foreach( member; __traits(allMembers, ObjectStateFlags) )
            static if( __traits(compiles, __traits(getMember, ObjectStateFlags, member) = false) )
                __traits(getMember, ObjectStateFlags, member) = false;
    }

    /**
     * Set each member to true.
     */
    void resumeAll()
    {
        foreach( member; __traits(allMembers, ObjectStateFlags) )
            static if( __traits(compiles, __traits(getMember, ObjectStateFlags, member) = true) )
                __traits(getMember, ObjectStateFlags, member) = true;
    }
}

/**
 * Manages all components and transform in the world. Can be overridden.
 */
shared class GameObject
{
private:
    Transform _transform;
    Material _material;
    Mesh _mesh;
    Animation _animation;
    Light _light;
    Camera _camera;
    GameObject _parent;
    GameObject[] _children;
    IComponent[TypeInfo] componentList;
    string _name;
    ObjectStateFlags* _stateFlags;
    bool canChangeName;
    static uint nextId = 1;

package:
    Scene scene;

public:
    /// The current transform of the object.
    mixin( RefGetter!( _transform, AccessModifier.Public ) );
    /// The Material belonging to the object.
    mixin( Property!( _material, AccessModifier.Public ) );
    /// The Mesh belonging to the object.
    mixin( Property!( _mesh, AccessModifier.Public ) );
    /// The animation on the object.
    mixin( Property!( _animation, AccessModifier.Public ) );
    /// The light attached to this object.
    mixin( Property!( _light, AccessModifier.Public ) );
    /// The camera attached to this object.
    mixin( Property!( _camera, AccessModifier.Public ) );
    /// The object that this object belongs to.
    mixin( Property!( _parent, AccessModifier.Public ) );
    /// All of the objects which list this as parent
    mixin( Property!( _children, AccessModifier.Public ) );
    /// The current update settings
    mixin( Property!( _stateFlags, AccessModifier.Public ) );
    /// The name of the object.
    mixin( Getter!_name );
    /// ditto
    mixin( ConditionalSetter!( _name, q{canChangeName}, AccessModifier.Public ) );
    /// The ID of the object
    immutable uint id;

    /**
     * Create a GameObject from a Yaml node.
     *
     * Params:
     *  yamlObj =           The YAML node to pull info from.
     *  scriptOverride =    The ClassInfo to use to create the object. Overrides YAML setting.
     *
     * Returns:
     *  A new game object with components and info pulled from yaml.
     */
    static shared(GameObject) createFromYaml( Node yamlObj, const ClassInfo scriptOverride = null )
    {
        shared GameObject obj;
        bool foundClassName;
        string prop, className;
        Node innerNode;

        string objName = yamlObj[ "Name" ].as!string;

        // Try to get from script
        if( scriptOverride !is null )
        {
            obj = cast(shared GameObject)scriptOverride.create();
        }
        else
        {
            foundClassName = Config.tryGet( "Script.ClassName", className, yamlObj );
            // Get class to create script from
            const ClassInfo scriptClass = foundClassName
                    ? ClassInfo.find( className )
                    : null;

            // Check that if a Script.ClassName was provided that it was valid
            if( foundClassName && scriptClass is null )
            {
                logWarning( objName, ": Unable to find Script ClassName: ", className );
            }

            if( Config.tryGet( "InstanceOf", prop, yamlObj ) )
            {
                obj = Prefabs[ prop ].createInstance( scriptClass );
            }
            else
            {
                obj = scriptClass
                        ? cast(shared GameObject)scriptClass.create()
                        : new shared GameObject;
            }
        }

        // set object name
        obj.name = objName;

        // Init transform
        if( Config.tryGet( "Transform", innerNode, yamlObj ) )
        {
            shared vec3 transVec;
            if( Config.tryGet( "Scale", transVec, innerNode ) )
                obj.transform.scale = shared vec3( transVec );
            if( Config.tryGet( "Position", transVec, innerNode ) )
                obj.transform.position = shared vec3( transVec );
            if( Config.tryGet( "Rotation", transVec, innerNode ) )
                obj.transform.rotation = quat.identity.rotatex( transVec.x.radians ).rotatey( transVec.y.radians ).rotatez( transVec.z.radians );
        }

        if( foundClassName && Config.tryGet( "Script.Fields", innerNode, yamlObj ) )
        {
            if( auto initParams = className in getInitParams )
                obj.initialize( (*initParams)( innerNode ) );
        }

        // If parent is specified, add it to the map
        if( Config.tryGet( "Parent", prop, yamlObj ) )
            logWarning( "Specifying parent objects by name is deprecated. Please add this as an inline child to ", prop, "." );

        if( Config.tryGet( "Children", innerNode, yamlObj ) )
        {
            if( innerNode.isSequence )
            {
                foreach( Node child; innerNode )
                {
                    if( child.isScalar )
                    {
                        // Add child name to map.
                        logWarning( "Specifing child objects by name is deprecated. Please add ", child.get!string, " as an inline child of ", objName, "." );
                    }
                    else
                    {
                        // If inline object, create it and add it as a child.
                        obj.addChild( GameObject.createFromYaml( child ) );
                    }
                }
            }
            else
            {
                logWarning( "Scalar values and mappings in 'Children' of ", obj.name, " are not supported, and it is being ignored." );
            }
        }

        // Init components
        foreach( string key, Node value; yamlObj )
        {
            if( key == "Name" || key == "Script" || key == "Parent" || key == "InstanceOf" || key == "Transform" || key == "Children" )
                continue;

            if( auto init = key in IComponent.initializers )
                obj.addComponent( (*init)( value, obj ) );
            else
                logWarning( "Unknown key: ", key );
        }

        return obj;
    }

    /**
     * Creates basic GameObject with transform and connection to transform's emitter.
     */
    this()
    {
        _transform = shared Transform( this );

        // Create default material
        material = new shared Material();
        id = nextId++;

        stateFlags = new ObjectStateFlags;
        stateFlags.resumeAll();

        name = typeid(this).name.split( '.' )[ $-1 ] ~ id.to!string;
        canChangeName = true;
    }

    /**
     * Called once per frame to update all children and components.
     */
    final void update()
    {
        if( stateFlags.update )
        {
            onUpdate();

            foreach( ci, component; componentList )
                component.update();
        }

        if( stateFlags.updateChildren )
            foreach( obj; children )
                obj.update();
    }

    /**
     * Called once per frame to draw all children.
     */
    final void draw()
    {
        onDraw();

        foreach( obj; children )
            obj.draw();
    }

    /**
     * Called when the game is shutting down, to shutdown all children.
     */
    final void shutdown()
    {
        onShutdown();

        foreach( obj; children )
            obj.shutdown();

        /*foreach_reverse( ci, component; componentList )
        {
            component.shutdown();
            componentList.remove( ci );
        }*/
    }

    /**
     * Adds a component to the object.
     */
    final void addComponent( T )( shared T newComponent ) if( is( T : IComponent ) )
    {
        if( newComponent )
            componentList[ typeid(T) ] = newComponent;
    }

    /**
     * Gets a component of the given type.
     */
    deprecated( "Make properties for any component being accessed." )
    final T getComponent( T )() if( is( T : IComponent ) )
    {
        return componentList[ typeid(T) ];
    }

    /**
     * Adds object to the children, adds it to the scene graph.
     *
     * Params:
     *  newChild =            The object to add.
     */
    final void addChild( shared GameObject newChild )
    {
        // Nothing to see here.
        if( cast()newChild.parent == cast()this )
            return;
        // Remove from current parent
        else if( newChild.parent && cast()newChild.parent != cast()this )
            newChild.parent.removeChild( newChild );

        _children ~= newChild;
        newChild.parent = this;
        newChild.canChangeName = false;

        // Get root object
        shared GameObject par;
        for( par = this; par.parent; par = par.parent ) { }

        shared GameObject[] objectChildren;
        {
            shared GameObject[] objs;
            objs ~= newChild;

            while( objs.length )
            {
                auto obj = objs[ 0 ];
                objs = objs[ 1..$ ];
                objectChildren ~= obj;

                foreach( child; obj.children )
                    objs ~= child;
            }
        }

        if( par.scene )
        {
            // If adding to the scene, make sure all new children are in.
            foreach( child; objectChildren )
            {
                par.scene.objectById[ child.id ] = child;
                par.scene.idByName[ child.name ] = child.id;
            }
        }

    }

    /**
     * Removes the given object as a child from this object.
     *
     * Params:
     *  oldChild =            The object to remove.
     */
    final void removeChild( shared GameObject oldChild )
    {
        children = children.remove( oldChild );

        oldChild.canChangeName = true;
        oldChild.parent = null;
    }

    /// Called on the update cycle.
    void onUpdate() { }
    /// Called on the draw cycle.
    void onDraw() { }
    /// Called on shutdown.
    void onShutdown() { }
    /// Called when the object collides with another object.
    void onCollision( GameObject other ) { }

    /// Allows for GameObjectInit to pass o to typed func.
    void initialize( Object o ) { }
}

private shared Object function( Node )[string] getInitParams;

/**
 * Class to extend when looking to use the onInitialize function.
 *
 * Type Params:
 *  T =             The type onInitialize will recieve.
 */
class GameObjectInit(T) : GameObject if( is( T == class ) )
{
    /// Function to override to get args from Fields field in YAML.
    abstract void onInitialize( T args );

    /// Overridden to give params to child class.
    final override void initialize( Object o )
    {
        onInitialize( cast(T)o );
    }

    /**
     * Registers subclasses with onInit function pointers/
     */
    shared static this()
    {
        foreach( mod; ModuleInfo )
        {
            foreach( klass; mod.localClasses )
            {
                if( klass.base == typeid(GameObjectInit!T) )
                {
                    getInitParams[ klass.name ] = &Config.getObject!T;
                }
            }
        }
    }
}

/**
 * Handles 3D Transformations for an object.
 * Stores position, rotation, and scale
 * and can generate a World matrix, worldPosition/Rotation (based on parents' transforms)
 * as well as forward, up, and right axes based on rotation
 */
private shared struct Transform
{
private:
    GameObject _owner;
    vec3 _prevPos;
    quat _prevRot;
    vec3 _prevScale;
    mat4 _matrix;

    /**
     * Default constructor, most often created by GameObjects.
     *
     * Params:
     *  obj =            The object the transform belongs to.
     */
    this( shared GameObject obj )
    {
        owner = obj;
        position = vec3(0,0,0);
        scale = vec3(1,1,1);
        rotation = quat.identity;
    }

public:
    // these should remain public fields, properties return copies not references
    /// The position of the object in local space.
    vec3 position;
    /// The rotation of the object in local space.
    quat rotation;
    /// The absolute scale of the object. Ignores parent scale.
    vec3 scale;

    /// The object which this belongs to.
    mixin( Property!( _owner, AccessModifier.Public ) );
    /// The world matrix of the transform.
    mixin( Getter!_matrix );
    //mixin( ThisDirtyGetter!( _matrix, updateMatrix ) );

    @disable this();

    /**
     * This returns the object's position relative to the world origin, not the parent.
     *
     * Returns: The object's position relative to the world origin, not the parent.
     */
    final @property shared(vec3) worldPosition() @safe pure nothrow
    {
        if( owner.parent is null )
            return position;
        else
            return (owner.parent.transform.matrix * shared vec4(position.x,position.y,position.z,1.0f)).xyz;
    }

    /**
     * This returns the object's rotation relative to the world origin, not the parent.
     *
     * Returns: The object's rotation relative to the world origin, not the parent.
     */
    final @property shared(quat) worldRotation() @safe pure nothrow
    {
        if( owner.parent is null )
            return rotation;
        else
            return owner.parent.transform.worldRotation * rotation;
    }

    /*
     * Check if current or a parent's matrix needs to be updated.
     * Called automatically when getting matrix.
     *
     * Returns: Whether or not the object is dirty.
     */
    final @property bool isDirty() @safe pure nothrow
    {
        bool result = position != _prevPos ||
                      rotation != _prevRot ||
                      scale != _prevScale;

        return owner.parent ? (result || owner.parent.transform.isDirty()) : result;
    }

    /*
     * Gets the forward axis of the current transform.
     *
     * Returns: The forward axis of the current transform.
     */
    final @property const shared(vec3) forward()
    {
        return shared vec3( -2 * (rotation.x * rotation.z + rotation.w * rotation.y),
                            -2 * (rotation.y * rotation.z - rotation.w * rotation.x),
                            -1 + 2 * (rotation.x * rotation.x + rotation.y * rotation.y ));
    }
    ///
    unittest
    {
        import std.stdio;
        import gl3n.math;
        writeln( "Dash Transform forward unittest" );

        auto trans = new shared Transform( null );
        auto forward = shared vec3( 0.0f, 1.0f, 0.0f );
        trans.rotation.rotatex( 90.radians );
        assert( almost_equal( trans.forward, forward ) );
    }

    /*
     * Gets the up axis of the current transform.
     *
     * Returns: The up axis of the current transform.
     */
    final  @property const shared(vec3) up()
    {
        return shared vec3( 2 * (rotation.x * rotation.y - rotation.w * rotation.z),
                        1 - 2 * (rotation.x * rotation.x + rotation.z * rotation.z),
                        2 * (rotation.y * rotation.z + rotation.w * rotation.x));
    }
    ///
    unittest
    {
        import std.stdio;
        import gl3n.math;
        writeln( "Dash Transform up unittest" );

        auto trans = new shared Transform( null );

        auto up = shared vec3( 0.0f, 0.0f, 1.0f );
        trans.rotation.rotatex( 90.radians );
        assert( almost_equal( trans.up, up ) );
    }

    /*
     * Gets the right axis of the current transform.
     *
     * Returns: The right axis of the current transform.
     */
    final  @property const shared(vec3) right()
    {
        return shared vec3( 1 - 2 * (rotation.y * rotation.y + rotation.z * rotation.z),
                        2 * (rotation.x * rotation.y + rotation.w * rotation.z),
                        2 * (rotation.x * rotation.z - rotation.w * rotation.y));
    }
    ///
    unittest
    {
        import std.stdio;
        import gl3n.math;
        writeln( "Dash Transform right unittest" );

        auto trans = new shared Transform( null );

        auto right = shared vec3( 0.0f, 0.0f, -1.0f );
        trans.rotation.rotatey( 90.radians );
        assert( almost_equal( trans.right, right ) );
    }

    /**
     * Rebuilds the object's matrix.
     */
    final void updateMatrix() @safe pure nothrow
    {
        _prevPos = position;
        _prevRot = rotation;
        _prevScale = scale;

        _matrix = mat4.identity;
        // Scale
        _matrix[ 0 ][ 0 ] = scale.x;
        _matrix[ 1 ][ 1 ] = scale.y;
        _matrix[ 2 ][ 2 ] = scale.z;

        // Rotate
        _matrix = _matrix * rotation.to_matrix!(4,4);

        // Translate
        _matrix[ 0 ][ 3 ] = position.x;
        _matrix[ 1 ][ 3 ] = position.y;
        _matrix[ 2 ][ 3 ] = position.z;

        // include parent objects' transforms
        if( owner.parent )
            _matrix = owner.parent.transform.matrix * _matrix;

        // force children to update to reflect changes to this
        // compensates for children that don't update properly when only parent is dirty
        foreach( child; owner.children )
            child.transform.updateMatrix();
    }
}
