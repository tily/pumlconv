require "java"
require "vendor/jars/net/sourceforge/plantuml/plantuml/8040/plantuml-8040.jar"
require "aws-sdk-core"
require "sinatra"
require "dotenv"
require "uuid"

Dotenv.load

java_import "java.io.ByteArrayOutputStream"
java_import "net.sourceforge.plantuml.SourceStringReader"

helpers do
  class PumlError < StandardError; end

  def convert(text)
    os = ByteArrayOutputStream.new
    reader = SourceStringReader.new(text)
    result = reader.generateImage(os)
    if result.nil?
      raise PumlError, 'description was nil'
    else
      String.from_java_bytes(os.toByteArray)
    end
  end

  def s3
    @s3 ||= Aws::S3::Client.new(
      endpoint: ENV["S3_ENDPOINT"],
      region: ENV["REGION"],
      signature_version: 's3',
      credentials: Aws::Credentials.new(
        ENV['ACCESS_KEY_ID'], ENV['SECRET_ACCESS_KEY'],
      )
    )
  end
end

post "/" do
  id = UUID.new.generate
  text = params[:text]

  begin
    png = convert(params[:text])
  rescue PumlError => e
    next {error: "parse error"}.to_json
  end

  s3.put_object(key: "#{id}.txt", body: text, bucket: ENV["BUCKET_NAME"], content_type: "text/plain")
  s3.put_object(key: "#{id}.png", body: png, bucket: ENV["BUCKET_NAME"], content_type: "image/png")

  {id: id}.to_json
end

get %r{^/(?<id>.+)\.(?<ext>txt|png)$} do
  content_type params[:ext] == 'png' ? 'image/png' : 'text/plain'
  object = s3.get_object(key: "#{params[:id]}.#{params[:ext]}", bucket: ENV["BUCKET_NAME"])
  object.body.read
end
