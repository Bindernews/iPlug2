#pragma once

#include <string>
#include <vector>
#include <map>
#include <memory>

class TTLDocument;
class TTLSubject;
class TTLObject;
using TTLString = std::string;


class ITTLWriter
{
public:

    virtual void indent(int count) = 0;
    virtual void writeIndent() = 0;
    virtual void write(const char *text, size_t len) = 0;
    virtual void setTabSize(size_t size) = 0;

    virtual void write(const TTLString& text);
    //virtual void write(const char *text);

    /** Write a newline and optionally indent. */
    virtual void newline(bool indent=false);
};

class FileTTLWriter : public ITTLWriter
{
public:
    FileTTLWriter(FILE *f);
    ~FileTTLWriter();

    virtual void indent(int count) override;
    virtual void writeIndent() override;
    virtual void write(const char *text, size_t len) override;
    virtual void setTabSize(size_t size) override;

private:
    FILE *mF;
    int mTab;
    int mTabSize;
};


class TTLDocument
{
public:
    TTLDocument();

    TTLDocument& addPrefix(const TTLString& name, const TTLString& uri);

    TTLSubject* subject(const TTLString& subject);

    void write(ITTLWriter &f);

public:
    static const char *ENDL;

private:
    std::vector<TTLString> mPrefixes;
    std::vector<TTLSubject*> mSubjects;
    std::map<TTLString, size_t> mSubjectMap;
};

class TTLObject
{
public:
    TTLObject();
    TTLObject(const TTLString &literal);
    TTLObject(TTLSubject *subj);
    TTLObject(TTLObject&&) = default;

    void write(ITTLWriter &f);

private:
    int mType;
    std::unique_ptr<TTLString> mStrVal;
    std::unique_ptr<TTLSubject> mSubjVal;
};


class TTLSubject
{
public:
    TTLSubject(const TTLString &name);
    TTLSubject();

    TTLSubject& reserve(const TTLString &verb);
    TTLSubject& add(const TTLString &verb, const TTLString &value);
    TTLSubject& add(const TTLString &verb, TTLSubject *value);
    TTLSubject& setMultilineThreshold(const TTLString &verb, int maxItems);

    template<typename ...Items>
    TTLSubject& addMany(const TTLString &verb, Items... items)
    {
        addHelper(verb, items...);
        return *this;
    }

    const TTLString& getName() const { return mName; }

    void write(ITTLWriter &f, bool endTriplet);

private:
    struct VerbVal {
        TTLString name;
        std::vector<TTLObject> values;
        int multilineThreshold;
    };

    template<typename T0, typename ...TN>
    inline void addHelper(const TTLString &verb, T0 item0, TN... items)
    {
        add(verb, item0);
        addHelper(verb, items...);
    }
    template<typename T0>
    inline void addHelper(const TTLString &verb, T0 item0)
    {
        add(verb, item0);
    }

    VerbVal& ensureVerb(const TTLString &verb);

    TTLString mName;
    std::vector<VerbVal> mVerbList;
    std::map<TTLString, int> mVerbMap;
};

