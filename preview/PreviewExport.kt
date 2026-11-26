package com.aivexus.rendezvous

import android.content.ClipData
import android.content.Intent
import android.net.Uri
import android.util.Base64
import android.webkit.JavascriptInterface
import android.widget.Toast
import androidx.core.content.FileProvider
import org.json.JSONArray
import java.io.File
import java.util.UUID
import java.util.zip.ZipEntry
import java.util.zip.ZipOutputStream

/** Local preview only. Opens a share composer; never sends automatically. */
class PreviewExport(private val activity: MainActivity) {
    private val xlsxType = "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"
    private fun email(s: String) = require(s.length <= 254 && Regex("^[^\\s@]+@[^\\s@]+\\.[^\\s@]+$").matches(s))
    private fun dir(): File = File(activity.cacheDir, "rv-export/" + UUID.randomUUID()).apply { check(mkdirs()) }
    private fun xml(s: String): String = s.filter { it == '\t' || it == '\n' || it == '\r' || it >= ' ' }.replace("&","&amp;").replace("<","&lt;").replace(">","&gt;").replace("\"","&quot;").replace("'","&apos;")
    private fun fail(e: Exception) { activity.runOnUiThread { Toast.makeText(activity, "Partage impossible : " + (e.message ?: "erreur"), Toast.LENGTH_LONG).show() } }
    private fun share(to: String, subject: String, body: String, files: List<File>, type: String, mode: String = "share") {
        val uris = ArrayList<Uri>(files.map { FileProvider.getUriForFile(activity, activity.packageName + ".fileprovider", it) })
        activity.runOnUiThread {
            try {
                val intent = Intent(if (uris.size > 1) Intent.ACTION_SEND_MULTIPLE else Intent.ACTION_SEND).apply {
                    this.type = type
                    putExtra(Intent.EXTRA_EMAIL, arrayOf(to))
                    putExtra(Intent.EXTRA_SUBJECT, subject)
                    putExtra(Intent.EXTRA_TEXT, body)
                    if (uris.size == 1) putExtra(Intent.EXTRA_STREAM, uris[0])
                    else if (uris.size > 1) putParcelableArrayListExtra(Intent.EXTRA_STREAM, uris)
                    if (uris.isNotEmpty()) {
                        clipData = ClipData.newUri(activity.contentResolver, "RendezVous", uris[0]).apply {
                            uris.drop(1).forEach { addItem(ClipData.Item(it)) }
                        }
                        addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                    }
                }
                if(mode=="email"){
                    val emailApps=activity.packageManager.queryIntentActivities(Intent(Intent.ACTION_SENDTO,Uri.parse("mailto:")),0)
                        .map{it.activityInfo.packageName}.distinct()
                    val candidates=emailApps.map{Intent(intent).setPackage(it)}.filter{it.resolveActivity(activity.packageManager)!=null}
                    if(candidates.isEmpty()){Toast.makeText(activity,"Aucune application e-mail compatible. Utilisez Partager.",Toast.LENGTH_LONG).show();return@runOnUiThread}
                    if(candidates.size==1) activity.startActivity(candidates.first())
                    else activity.startActivity(Intent.createChooser(candidates.first(),"Choisir votre application e-mail").apply{
                        putExtra(Intent.EXTRA_INITIAL_INTENTS,candidates.drop(1).toTypedArray())
                    })
                }else activity.startActivity(Intent.createChooser(intent, "Partager le fichier"))
            } catch(e: Exception) { fail(e) }
        }
    }
    @JavascriptInterface fun shareExcel(payload: String, to: String) = shareExcelMode(payload,to,"share")
    @JavascriptInterface fun shareExcelMode(payload: String, to: String, mode: String) {
        try {
            email(to); require(payload.length <= 4000000)
            val rows=JSONArray(payload); require(rows.length() in 1..10001)
            val file=File(dir(),"RendezVous.xlsx")
            ZipOutputStream(file.outputStream()).use { zip ->
                fun add(name: String, value: String) {
                    zip.putNextEntry(ZipEntry(name)); zip.write(value.toByteArray(Charsets.UTF_8)); zip.closeEntry()
                }
                add("[Content_Types].xml", """<?xml version="1.0" encoding="UTF-8"?><Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="xml" ContentType="application/xml"/><Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/><Override PartName="/xl/worksheets/sheet1.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/></Types>""")
                add("_rels/.rels", """<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/></Relationships>""")
                add("xl/workbook.xml", """<workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"><sheets><sheet name="Rendez-vous" sheetId="1" r:id="rId1"/></sheets></workbook>""")
                add("xl/_rels/workbook.xml.rels", """<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet1.xml"/></Relationships>""")
                val sheet = StringBuilder("""<?xml version="1.0" encoding="UTF-8"?><worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"><sheetData>""")
                for(i in 0 until rows.length()){
                    val row=rows.getJSONArray(i); require(row.length()==11)
                    sheet.append("<row r=\"").append(i+1).append("\">")
                    for(j in 0 until row.length()){
                        val ref=('A'.code+j).toChar().toString()+(i+1)
                        sheet.append("<c r=\"").append(ref).append("\" t=\"inlineStr\"><is><t xml:space=\"preserve\">").append(xml(row.optString(j,""))).append("</t></is></c>")
                    }
                    sheet.append("</row>")
                }
                sheet.append("</sheetData></worksheet>")
                add("xl/worksheets/sheet1.xml",sheet.toString())
            }
            share(to,"Export RendezVous — démonstration","Vous trouverez les rendez-vous fictifs dans le fichier Excel.",listOf(file),xlsxType,mode)
        } catch(e: Exception){fail(e)}
    }
    @JavascriptInterface fun shareDocuments(payload: String,to: String,summary: String){
        try{
            email(to); require(payload.length <= 24000000 && summary.length <= 4000)
            val docs=JSONArray(payload); require(docs.length()<=8)
            val root=dir(); val files=mutableListOf<File>()
            for(i in 0 until docs.length()){
                val item=docs.getJSONObject(i)
                val name=item.getString("name").replace(Regex("[^\\p{L}\\p{N}._ -]"),"_").take(100).trim('.',' ')
                require(name.isNotBlank())
                val mime=item.getString("mime")
                require(mime in listOf("application/pdf","image/png","image/jpeg","text/plain"))
                val data=Base64.decode(item.getString("data"),Base64.DEFAULT); require(data.size in 1..2097152)
                val f=File(root,(i+1).toString()+"-"+name); f.writeBytes(data); files.add(f)
            }
            share(to,"Rendez-vous — démonstration",summary,files,if(files.isEmpty()) "text/plain" else "*/*")
        }catch(e:Exception){fail(e)}
    }

    @JavascriptInterface fun shareAppointmentBundle(payload: String,to: String,summary: String,appointmentId: String,mode: String){
        try{
            email(to); require(mode in listOf("email","share"))
            require(payload.length <= 24000000 && summary.length <= 4000)
            require(appointmentId.matches(Regex("[A-Za-z0-9_-]{1,100}")))
            val docs=JSONArray(payload); require(docs.length()<=8)
            val bundle=File(dir(),"RendezVous-"+appointmentId+".zip")
            val references=StringBuilder("Rendez-vous : "+appointmentId+"\n"+summary+"\n\nDocuments : "+docs.length()+"\n")
            ZipOutputStream(bundle.outputStream()).use { zip ->
                for(i in 0 until docs.length()){
                    val item=docs.getJSONObject(i)
                    val name=item.getString("name").replace(Regex("[^\\p{L}\\p{N}._ -]"),"_").take(100).trim('.',' ')
                    require(name.isNotBlank())
                    val mime=item.optString("mime")
                    require(mime in listOf("application/pdf","image/png","image/jpeg","image/gif","image/webp","image/bmp","text/plain","application/octet-stream",""))
                    val data=Base64.decode(item.getString("data"),Base64.DEFAULT); require(data.size in 1..2097152)
                    val entry="Documents/"+(i+1)+"-"+name
                    zip.putNextEntry(ZipEntry(entry));zip.write(data);zip.closeEntry()
                    val digest=java.security.MessageDigest.getInstance("SHA-256").digest(data).joinToString(""){ "%02x".format(it.toInt() and 255) }
                    references.append(entry).append("\nID document : ").append(item.optString("id")).append("\nExpéditeur (profil démo) : ").append(item.optString("from")).append("\nDate : ").append(item.optString("date")).append("\nSHA-256 : ").append(digest).append("\n\n")
                }
                zip.putNextEntry(ZipEntry("RendezVous.txt"));zip.write(references.toString().toByteArray(Charsets.UTF_8));zip.closeEntry()
            }
            java.util.zip.ZipFile(bundle).use{z->require(z.size()==docs.length()+1);require(z.getEntry("RendezVous.txt")!=null)}
            share(to,"Rendez-vous — démonstration",summary+"\nDocuments joints : "+docs.length(),listOf(bundle),"application/zip",mode)
        }catch(e:Exception){fail(e)}
    }
}
